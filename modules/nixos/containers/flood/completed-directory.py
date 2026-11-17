"""Resolve Flood's URI-encoded d.custom1 label to one safe completed folder."""

import os
from pathlib import Path
import re
import sys
from urllib.parse import unquote


def destination(root, encoded_labels):
    root = Path(root)
    if not root.is_absolute():
        raise ValueError("completed root must be absolute")
    if not encoded_labels:
        return root
    # Flood encodes each label separately, then joins them with a comma.
    # A comma *inside* a label is %2C, not a second label.
    if "," in encoded_labels:
        raise ValueError("choose one Flood label before completing this torrent")
    if re.search(r"%(?![0-9a-fA-F]{2})", encoded_labels):
        raise ValueError("invalid label encoding")
    label = unquote(encoded_labels, encoding="utf-8", errors="strict")
    if (label in ("", ".", "..") or "/" in label or "\\" in label
            or any(ord(character) < 32 or ord(character) == 127 for character in label)
            or len(label.encode("utf-8")) > 255):
        raise ValueError("Flood label must be a single safe folder name")
    return root / label


def prepare(root, encoded_labels):
    target = destination(root, encoded_labels)
    # Refuse symlinks instead of allowing a label to redirect the move out of
    # completed/. Existing folders retain their permissions and ownership.
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    descriptor = os.open(root, flags)
    try:
        if target != Path(root):
            try:
                os.mkdir(target.name, mode=0o775, dir_fd=descriptor)
            except FileExistsError:
                pass
            child = os.open(target.name, flags, dir_fd=descriptor)
            os.close(child)
    finally:
        os.close(descriptor)
    return target


if __name__ == "__main__":
    try:
        # rTorrent's execute.capture includes newlines; return a bare path.
        sys.stdout.write(str(prepare(sys.argv[1], sys.argv[2])))
    except (OSError, ValueError) as error:
        sys.exit(f"Cannot route completed torrent: {error}")
