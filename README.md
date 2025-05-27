# mcp_server

Model Context Protocol (MCP) implementation in Ruby 2.4.xx.

## Overview

`mcp_server` is a Ruby-based implementation of the Model Context Protocol (MCP), designed to facilitate communication and data exchange between modeling software and external clients. It provides a server interface for handling MCP requests, supporting multiple transport protocols and integration with Innovyze InfoWorks ICM and WS Pro environments.

## Features

- Supports multiple MCP transport protocols (STDIO, TCP and HTTP)
- Modular server architecture for easy extension
- Ruby 2.4.xx compatibility

## Directory Structure

```
.
├── Gemfile                  # Ruby gem dependencies
├── LICENSE                  # License information
├── README.md                # Project documentation
├── mcp_server.gemspec       # Gem specification
├── lib/
│   └── mcp_server.rb        # Main library file
├── scripts/
│   ├── icm_mcp_server.rb    # ICM-specific server script
│   ├── mcp_server.rb        # General server script
```

## Installation

1. Ensure you have Ruby 2.4.xx installed.
2. Clone this repository:
   ```powershell
   git clone <repository-url>
   cd mcp_server
   ```
3. Install dependencies:
   ```powershell
   bundle install
   ```

## Usage

You can run the MCP server using the provided scripts. For example:

```powershell
ruby scripts/icm_mcp_server.rb
```

To use a specific protocol version, run the corresponding script in `scripts/v0x/`:

```powershell
ruby scripts/v01/mcp_server.rb
```

For integration with InfoWorks ICM:

```powershell
ruby scripts/icm_mcp_server.rb
```

## VS Code and Claude Desktop Setup

### VS Code Configuration

1. Open the project folder in VS Code.
2. Ensure your Ruby interpreter is set to version 2.4.xx.
3. Create mcp.json under .vscode folder
   ```json
   {
    "mcpServers": 
        {
            "ICM_MCP": {
                "command": "iexchange",
                "args": [
                    "{script_path}/{your_server_script_name}.rb",
                    "/ICM"
                ],
                "env": {}
            }
        }
    }
   ```
   if vscode doesnt understand the iexchange command enter full path to iexchange.exe
   i.e. C:\Program Files\Innovyze\Infoworks ICM 2024.5c\iexchange.exe

### Claude Desktop Setup

1. Download and install Claude Desktop from the official source.
2. Open claude desktop configuration from File -> Settings -> Developer and click on 'Edit config'
3. And add same json file used for vscode.
4. Restart claude desktop and Enjoy interacting with your application.

## Contributing

Contributions are welcome! Please fork the repository and submit a pull request.

## License

See the [LICENSE](LICENSE) file for details.
