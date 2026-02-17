{
  name = "pretty-mermaid";
  version = "1.0.0";
  description = "Render beautiful Mermaid diagrams as SVG or ASCII art. Supports 15+ themes, 5 diagram types (flowchart, sequence, state, class, ER), and ultra-fast rendering. Use when: user asks to render a mermaid diagram, create flowchart/sequence/state diagrams, apply themes, batch process diagrams, visualize architecture/workflows/data models.";
  allowed-tools = [
    "Read"
    "Write"
    "Edit"
    "Bash"
    "Glob"
    "AskUserQuestion"
  ];
  content = ''
    # Pretty Mermaid

    Render stunning, professionally-styled Mermaid diagrams with one command. Supports SVG for web/docs and ASCII for terminals.

    ## Quick Start

    ### Render a Single Diagram

    **From a file:**
    ```bash
    npx beautiful-mermaid render \
      --input diagram.mmd \
      --output diagram.svg \
      --format svg \
      --theme tokyo-night
    ```

    **From user-provided Mermaid code:**
    1. Save the code to a `.mmd` file
    2. Run the render script with desired theme

    ### Batch Render Multiple Diagrams

    ```bash
    npx beautiful-mermaid batch \
      --input-dir ./diagrams \
      --output-dir ./output \
      --format svg \
      --theme dracula \
      --workers 4
    ```

    ### ASCII Output (Terminal-Friendly)

    ```bash
    npx beautiful-mermaid render \
      --input diagram.mmd \
      --format ascii
    ```

    ---

    ## Workflow Decision Tree

    **Step 1: What does the user want?**
    - **Render existing Mermaid code** → Go to [Rendering](#rendering-diagrams)
    - **Create new diagram** → Go to [Creating](#creating-diagrams)
    - **Apply/change theme** → Go to [Theming](#theming)
    - **Batch process** → Go to [Batch Rendering](#batch-rendering)

    **Step 2: Choose output format**
    - **SVG** (web, docs, presentations) → `--format svg`
    - **ASCII** (terminal, logs, plain text) → `--format ascii`

    **Step 3: Select theme**
    - **Dark mode docs** → `tokyo-night` (recommended)
    - **Light mode docs** → `github-light`
    - **Vibrant colors** → `dracula`
    - **See all themes** → Run `npx beautiful-mermaid themes`

    ---

    ## Rendering Diagrams

    ### From File

    When user provides a `.mmd` file or Mermaid code block:

    1. **Save to file** (if code block):
       ```bash
       cat > diagram.mmd << 'EOF'
       flowchart LR
           A[Start] --> B[End]
       EOF
       ```

    2. **Render with theme**:
       ```bash
       npx beautiful-mermaid render \
         --input diagram.mmd \
         --output diagram.svg \
         --theme tokyo-night
       ```

    3. **Verify output**:
       - SVG: Open in browser or embed in docs
       - ASCII: Display in terminal

    ### Output Formats

    **SVG (Scalable Vector Graphics)**
    - Best for: Web pages, documentation, presentations
    - Features: Full color support, transparency, scalable
    - Usage: `--format svg --output diagram.svg`

    **ASCII (Terminal Art)**
    - Best for: Terminal output, plain text logs, README files
    - Features: Pure text, works anywhere, no dependencies
    - Usage: `--format ascii` (prints to stdout)

    ### Advanced Options

    **Custom Colors** (overrides theme):
    ```bash
    npx beautiful-mermaid render \
      --input diagram.mmd \
      --bg "#1a1b26" \
      --fg "#a9b1d6" \
      --accent "#7aa2f7" \
      --output custom.svg
    ```

    **Transparent Background**:
    ```bash
    npx beautiful-mermaid render \
      --input diagram.mmd \
      --transparent \
      --output transparent.svg
    ```

    ---

    ## Creating Diagrams

    ### Diagram Type Reference

    **Flowchart** - Processes, workflows, decision trees
    ```mermaid
    flowchart LR
        A[Start] --> B{Decision}
        B -->|Yes| C[Action]
        B -->|No| D[End]
    ```

    **Sequence** - API calls, interactions, message flows
    ```mermaid
    sequenceDiagram
        User->>Server: Request
        Server-->>User: Response
    ```

    **State** - Application states, lifecycle, FSM
    ```mermaid
    stateDiagram-v2
        [*] --> Idle
        Idle --> Loading
        Loading --> [*]
    ```

    **Class** - Object models, architecture, relationships
    ```mermaid
    classDiagram
        User --> Post: creates
        Post --> Comment: has
    ```

    **ER** - Database schema, data models
    ```mermaid
    erDiagram
        USER ||--o{ ORDER : places
        ORDER ||--|{ ORDER_ITEM : contains
    ```

    ### From User Requirements

    **Step 1: Identify diagram type**
    - **Process/workflow** → Flowchart
    - **API/interaction** → Sequence
    - **States/lifecycle** → State
    - **Object model** → Class
    - **Database** → ER

    **Step 2: Create diagram file**
    ```bash
    cat > user-diagram.mmd << 'EOF'
    # [Insert generated Mermaid code]
    EOF
    ```

    **Step 3: Render and iterate**
    ```bash
    npx beautiful-mermaid render \
      --input user-diagram.mmd \
      --output preview.svg \
      --theme tokyo-night
    ```

    ---

    ## Theming

    ### Available Themes

    | Theme | Type | Background | Best For |
    |-------|------|------------|----------|
    | `tokyo-night` | Dark | #1a1b26 | Modern dev docs (recommended) |
    | `tokyo-night-storm` | Dark | #24283b | OLED screens |
    | `tokyo-night-light` | Light | #d5d6db | Soft light mode |
    | `dracula` | Dark | #282a36 | Vibrant, high contrast |
    | `github-dark` | Dark | #0d1117 | GitHub docs |
    | `github-light` | Light | #ffffff | GitHub README |
    | `nord` | Dark | #2e3440 | Professional, cool tones |
    | `nord-light` | Light | #eceff4 | Light Nord variant |
    | `catppuccin-mocha` | Dark | #1e1e2e | Warm, comfortable |
    | `catppuccin-latte` | Light | #eff1f5 | Light Catppuccin |
    | `zinc-dark` | Dark | #18181B | Minimal dark |
    | `zinc-light` | Light | #FFFFFF | Printable, high contrast |
    | `solarized-dark` | Dark | #002b36 | Scientific papers |
    | `solarized-light` | Light | #fdf6e3 | Academic docs |
    | `one-dark` | Dark | #282c34 | Atom-style |

    ### Theme Selection Guide

    **For dark mode documentation:**
    - `tokyo-night` - Modern, developer-friendly
    - `github-dark` - Familiar GitHub style
    - `dracula` - Vibrant, high contrast
    - `nord` - Cool, minimalist

    **For light mode documentation:**
    - `github-light` - Clean, professional
    - `zinc-light` - High contrast, printable
    - `catppuccin-latte` - Warm, friendly

    ### Apply Theme to Diagram

    ```bash
    npx beautiful-mermaid render \
      --input diagram.mmd \
      --output themed.svg \
      --theme tokyo-night
    ```

    ---

    ## Batch Rendering

    ### Batch Render Directory

    **Step 1: Organize diagrams**
    ```bash
    diagrams/
    ├── architecture.mmd
    ├── workflow.mmd
    └── database.mmd
    ```

    **Step 2: Batch render**
    ```bash
    npx beautiful-mermaid batch \
      --input-dir ./diagrams \
      --output-dir ./rendered \
      --format svg \
      --theme tokyo-night \
      --workers 4
    ```

    ---

    ## Diagram Syntax Reference

    ### Flowchart Node Shapes
    - `[Text]` - Rectangle
    - `([Text])` - Stadium (rounded)
    - `[(Text)]` - Cylindrical (database)
    - `((Text))` - Circle
    - `{Text}` - Rhombus (decision)
    - `{{Text}}` - Hexagon

    ### Flowchart Connections
    - `-->` - Arrow
    - `---` - Line
    - `-.->` - Dotted arrow
    - `==>` - Thick arrow
    - `--text-->` - Arrow with label

    ### Flowchart Direction
    - `LR` - Left to Right
    - `RL` - Right to Left
    - `TB` / `TD` - Top to Bottom
    - `BT` - Bottom to Top

    ### Sequence Message Types
    - `->>` - Solid arrow
    - `-->>` - Dotted arrow
    - `-x` - Solid with cross
    - `--x` - Dotted with cross

    ### Sequence Loops & Alt
    ```mermaid
    sequenceDiagram
        loop Every minute
            A->>B: Ping
        end

        alt Success
            B-->>A: OK
        else Failure
            B-->>A: Error
        end
    ```

    ### ER Cardinality
    - `||--||` - One to one
    - `||--o{` - One to zero or more
    - `||--|{` - One to one or more
    - `}o--o{` - Zero or more to zero or more

    ### Class Diagram Visibility
    - `+` Public
    - `-` Private
    - `#` Protected
    - `~` Package/Internal

    ### Class Relationships
    - `--|>` - Inheritance
    - `--*` - Composition
    - `--o` - Aggregation
    - `-->` - Association
    - `..>` - Dependency

    ---

    ## Common Use Cases

    ### 1. Architecture Diagram for Documentation

    ```bash
    npx beautiful-mermaid render \
      --input architecture.mmd \
      --output docs/architecture.svg \
      --theme github-dark \
      --transparent
    ```

    ### 2. API Sequence Diagram

    ```bash
    npx beautiful-mermaid render \
      --input api-flow.mmd \
      --output api-sequence.svg \
      --theme tokyo-night
    ```

    ### 3. Database Schema Visualization

    ```bash
    npx beautiful-mermaid render \
      --input schema.mmd \
      --output database-schema.svg \
      --theme dracula
    ```

    ### 4. Terminal-Friendly Workflow

    ```bash
    npx beautiful-mermaid render \
      --input workflow.mmd \
      --format ascii > workflow.txt
    ```

    ---

    ## Troubleshooting

    ### Invalid Mermaid Syntax
    **Solution:**
    1. Test on https://mermaid.live/
    2. Check for common errors:
       - Missing spaces in `A --> B`
       - Incorrect node shape syntax
       - Unclosed brackets

    ### beautiful-mermaid Not Installed
    ```bash
    npx beautiful-mermaid --version
    # or install globally
    npm install -g beautiful-mermaid
    ```

    ---

    ## Best Practices

    ### Performance
    - Batch render for 3+ diagrams (parallel processing)
    - Keep diagrams under 50 nodes for fast rendering
    - Use ASCII for quick previews

    ### Quality
    - Use `tokyo-night` or `github-dark` for technical docs
    - Add transparency for dark/light mode compatibility: `--transparent`
    - Test theme in target environment before batch rendering

    ### Accessibility
    - Use high-contrast themes for presentations
    - Add text labels to all connections
    - Avoid color-only information encoding
  '';
}
