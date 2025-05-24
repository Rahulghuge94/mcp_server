#!/usr/bin/env ruby
# Model Context Protocol (MCP) Implementation for Ruby 2.4
# A complete implementation of the MCP specification

require 'json'
require 'socket'
require 'logger'
require 'uri'

module MCP
  VERSION = "1.1.0"
  
  # MCP Protocol Constants
  PROTOCOL_VERSION = "2024-11-05"
  
  # Message Types
  class MessageType
    REQUEST = "request"
    RESPONSE = "response" 
    NOTIFICATION = "notification"
  end
  
  # Standard MCP Methods
  class Methods
    # Initialization
    INITIALIZE = "initialize"
    
    # Capabilities
    LIST_TOOLS = "tools/list"
    CALL_TOOL = "tools/call"
    LIST_RESOURCES = "resources/list"
    READ_RESOURCE = "resources/read"
    SUBSCRIBE_RESOURCE = "resources/subscribe"
    UNSUBSCRIBE_RESOURCE = "resources/unsubscribe"
    LIST_PROMPTS = "prompts/list"
    GET_PROMPT = "prompts/get"
    
    # Logging
    SET_LOG_LEVEL = "logging/setLevel"
    
    # Notifications
    RESOURCE_UPDATED = "notifications/resources/updated"
    RESOURCE_LIST_CHANGED = "notifications/resources/list_changed"
    TOOL_LIST_CHANGED = "notifications/tools/list_changed"
    PROMPT_LIST_CHANGED = "notifications/prompts/list_changed"
    LOG_MESSAGE = "notifications/message"
  end
  
  # MCP Error Codes
  class ErrorCodes
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603
    
    # MCP Specific Errors
    INVALID_TOOL = -32000
    RESOURCE_NOT_FOUND = -32001
    RESOURCE_ACCESS_DENIED = -32002
    PROMPT_NOT_FOUND = -32003
  end
  
  # Base MCP Exception
  class MCPError < StandardError
    attr_reader :code, :data
    
    def initialize(message, code = ErrorCodes::INTERNAL_ERROR, data = nil)
      super(message)
      @code = code
      @data = data
    end
    
    def to_hash
      error = { code: @code, message: message }
      error[:data] = @data if @data
      error
    end
  end
  
  # MCP Message Structure
  class Message
    attr_accessor :jsonrpc, :id, :method, :params, :result, :error
    
    def initialize(jsonrpc: "2.0", id: nil, method: nil, params: nil, result: nil, error: nil)
      @jsonrpc = jsonrpc
      @id = id
      @method = method
      @params = params
      @result = result
      @error = error
    end
    
    def request?
      !@method.nil?
    end
    
    def response?
      @method.nil? && (!@result.nil? || !@error.nil?)
    end
    
    def notification?
      @method && @id.nil?
    end
    
    def to_hash
      hash = { jsonrpc: @jsonrpc }
      hash[:id] = @id if @id
      hash[:method] = @method if @method
      hash[:params] = @params if @params
      hash[:result] = @result if @result
      hash[:error] = @error if @error
      hash
    end
    
    def to_json
      JSON.generate(to_hash)
    end
    
    def self.from_hash(hash)
      new(
        jsonrpc: hash["jsonrpc"] || hash[:jsonrpc],
        id: hash["id"] || hash[:id],
        method: hash["method"] || hash[:method],
        params: hash["params"] || hash[:params],
        result: hash["result"] || hash[:result],
        error: hash["error"] || hash[:error]
      )
    end
    
    def self.from_json(json_str)
      hash = JSON.parse(json_str)
      from_hash(hash)
    rescue JSON::ParserError => e
      raise MCPError.new("Parse error: #{e.message}", ErrorCodes::PARSE_ERROR)
    end
  end
  
  # Tool Definition
  class Tool
    attr_reader :name, :description, :input_schema
    
    def initialize(name, description, input_schema = nil)
      @name = name
      @description = description
      @input_schema = input_schema || { type: "object", properties: {} }
    end
    
    def to_hash
      {
        name: @name,
        description: @description,
        inputSchema: @input_schema
      }
    end
  end
  
  # Resource Definition
  class Resource
    attr_reader :uri, :name, :description, :mime_type
    
    def initialize(uri, name = nil, description = nil, mime_type = nil)
      @uri = uri
      @name = name
      @description = description
      @mime_type = mime_type
    end
    
    def to_hash
      hash = { uri: @uri }
      hash[:name] = @name if @name
      hash[:description] = @description if @description
      hash[:mimeType] = @mime_type if @mime_type
      hash
    end
  end
  
  # Prompt Definition
  class Prompt
    attr_reader :name, :description, :arguments
    
    def initialize(name, description = nil, arguments = nil)
      @name = name
      @description = description
      @arguments = arguments || []
    end
    
    def to_hash
      hash = { name: @name }
      hash[:description] = @description if @description
      hash[:arguments] = @arguments unless @arguments.empty?
      hash
    end
  end
  
  # MCP Transport Interface
  class Transport
    def send_message(message)
      raise NotImplementedError, "Subclasses must implement send_message"
    end
    
    def receive_message
      raise NotImplementedError, "Subclasses must implement receive_message"
    end
    
    def close
      # Default implementation - override if needed
    end
  end
  
  # Standard I/O Transport
  class StdioTransport < Transport
    def initialize
      @input = STDIN
      @output = STDOUT
      @logger = Logger.new(STDERR)
      @logger.level = Logger::INFO
    end
    
    def send_message(message)
      json_str = message.to_json
      @output.puts(json_str)
      @output.flush
      @logger.debug("Sent: #{json_str}")
    end
    
    def receive_message
      line = @input.gets
      return nil unless line
      
      line = line.strip
      return nil if line.empty?
      
      @logger.debug("Received: #{line}")
      Message.from_json(line)
    end
  end
  
  # TCP Transport
  class TCPTransport < Transport
    def initialize(host, port)
      @host = host
      @port = port
      @socket = nil
      @logger = Logger.new(STDERR)
      @logger.level = Logger::INFO
    end
    
    def connect
      @socket = TCPSocket.new(@host, @port)
      @logger.info("Connected to #{@host}:#{@port}")
    end
    
    def send_message(message)
      raise "Not connected" unless @socket
      
      json_str = message.to_json
      @socket.puts(json_str)
      @socket.flush
      @logger.debug("Sent: #{json_str}")
    end
    
    def receive_message
      raise "Not connected" unless @socket
      
      line = @socket.gets
      return nil unless line
      
      line = line.strip
      return nil if line.empty?
      
      @logger.debug("Received: #{line}")
      Message.from_json(line)
    end
    
    def close
      @socket&.close
      @socket = nil
      @logger.info("Connection closed")
    end
  end
  
  # Base MCP Server
  class Server
    attr_reader :name, :version, :capabilities
    
    def initialize(name, version = "1.0.0")
      @name = name
      @version = version
      @capabilities = {
        tools: {},
        resources: {},
        prompts: {},
        logging: {}
      }
      @tools = {}
      @resources = {}
      @prompts = {}
      @transport = nil
      @logger = Logger.new(STDERR)
      @logger.level = Logger::INFO
      @initialized = false
      @request_id = 0
    end
    
    def set_transport(transport)
      @transport = transport
    end
    
    def add_tool(tool, &handler)
      @tools[tool.name] = { tool: tool, handler: handler }
      @capabilities[:tools] = { listChanged: true }
    end
    
    def add_resource(resource, &handler)
      @resources[resource.uri] = { resource: resource, handler: handler }
      @capabilities[:resources] = { subscribe: true, listChanged: true }
    end
    
    def add_prompt(prompt, &handler)
      @prompts[prompt.name] = { prompt: prompt, handler: handler }
      @capabilities[:prompts] = { listChanged: true }
    end
    
    def run
      raise "No transport set" unless @transport
      
      @logger.info("Starting MCP Server: #{@name} v#{@version}")
      
      loop do
        begin
          message = @transport.receive_message
          break unless message
          
          handle_message(message)
        rescue MCPError => e
          @logger.error("MCP Error: #{e.message}")
          send_error_response(nil, e)
        rescue => e
          @logger.error("Unexpected error: #{e.message}")
          @logger.error(e.backtrace.join("\n"))
          send_error_response(nil, MCPError.new("Internal server error", ErrorCodes::INTERNAL_ERROR))
        end
      end
    ensure
      @transport&.close
    end
    
    private
    
    def handle_message(message)
      if message.request?
        handle_request(message)
      elsif message.response?
        handle_response(message)
      elsif message.notification?
        handle_notification(message)
      else
        raise MCPError.new("Invalid message format", ErrorCodes::INVALID_REQUEST)
      end
    end
    
    def handle_request(message)
      case message.method
      when Methods::INITIALIZE
        handle_initialize(message)
      when Methods::LIST_TOOLS
        handle_list_tools(message)
      when Methods::CALL_TOOL
        handle_call_tool(message)
      when Methods::LIST_RESOURCES
        handle_list_resources(message)
      when Methods::READ_RESOURCE
        handle_read_resource(message)
      when Methods::LIST_PROMPTS
        handle_list_prompts(message)
      when Methods::GET_PROMPT
        handle_get_prompt(message)
      when Methods::SET_LOG_LEVEL
        handle_set_log_level(message)
      else
        raise MCPError.new("Method not found: #{message.method}", ErrorCodes::METHOD_NOT_FOUND)
      end
    end
    
    def handle_response(message)
      # Handle responses to our requests (if we made any)
      @logger.debug("Received response: #{message.id}")
    end
    
    def handle_notification(message)
      @logger.debug("Received notification: #{message.method}")
    end
    
    def handle_initialize(message)
      params = message.params || {}
      
      result = {
        protocolVersion: PROTOCOL_VERSION,
        serverInfo: {
          name: @name,
          version: @version
        },
        capabilities: @capabilities
      }
      
      @initialized = true
      send_response(message.id, result)
      @logger.info("Server initialized")
    end
    
    def handle_list_tools(message)
      tools = @tools.values.map { |t| t[:tool].to_hash }
      send_response(message.id, { tools: tools })
    end
    
    def handle_call_tool(message)
      check_initialized
      
      params = message.params || {}
      tool_name = params["name"]
      arguments = params["arguments"] || {}
      
      raise MCPError.new("Tool name required", ErrorCodes::INVALID_PARAMS) unless tool_name
      
      tool_info = @tools[tool_name]
      raise MCPError.new("Tool not found: #{tool_name}", ErrorCodes::INVALID_TOOL) unless tool_info
      
      begin
        result = tool_info[:handler].call(arguments)
        send_response(message.id, {
          content: [
            {
              type: "text",
              text: result.to_s
            }
          ]
        })
      rescue => e
        raise MCPError.new("Tool execution failed: #{e.message}", ErrorCodes::INTERNAL_ERROR)
      end
    end
    
    def handle_list_resources(message)
      check_initialized
      
      resources = @resources.values.map { |r| r[:resource].to_hash }
      send_response(message.id, { resources: resources })
    end
    
    def handle_read_resource(message)
      check_initialized
      
      params = message.params || {}
      uri = params["uri"]
      
      raise MCPError.new("Resource URI required", ErrorCodes::INVALID_PARAMS) unless uri
      
      resource_info = @resources[uri]
      raise MCPError.new("Resource not found: #{uri}", ErrorCodes::RESOURCE_NOT_FOUND) unless resource_info
      
      begin
        content = resource_info[:handler].call(uri)
        send_response(message.id, {
          contents: [
            {
              uri: uri,
              mimeType: resource_info[:resource].mime_type || "text/plain",
              text: content.to_s
            }
          ]
        })
      rescue => e
        raise MCPError.new("Resource read failed: #{e.message}", ErrorCodes::INTERNAL_ERROR)
      end
    end
    
    def handle_list_prompts(message)
      check_initialized
      
      prompts = @prompts.values.map { |p| p[:prompt].to_hash }
      send_response(message.id, { prompts: prompts })
    end
    
    def handle_get_prompt(message)
      check_initialized
      
      params = message.params || {}
      prompt_name = params["name"]
      arguments = params["arguments"] || {}
      
      raise MCPError.new("Prompt name required", ErrorCodes::INVALID_PARAMS) unless prompt_name
      
      prompt_info = @prompts[prompt_name]
      raise MCPError.new("Prompt not found: #{prompt_name}", ErrorCodes::PROMPT_NOT_FOUND) unless prompt_info
      
      begin
        content = prompt_info[:handler].call(arguments)
        send_response(message.id, {
          description: prompt_info[:prompt].description,
          messages: [
            {
              role: "user",
              content: {
                type: "text",
                text: content.to_s
              }
            }
          ]
        })
      rescue => e
        raise MCPError.new("Prompt generation failed: #{e.message}", ErrorCodes::INTERNAL_ERROR)
      end
    end
    
    def handle_set_log_level(message)
      params = message.params || {}
      level = params["level"]
      
      case level
      when "debug"
        @logger.level = Logger::DEBUG
      when "info"
        @logger.level = Logger::INFO
      when "warn"
        @logger.level = Logger::WARN
      when "error"
        @logger.level = Logger::ERROR
      else
        raise MCPError.new("Invalid log level: #{level}", ErrorCodes::INVALID_PARAMS)
      end
      
      send_response(message.id, {})
      @logger.info("Log level set to: #{level}")
    end
    
    def send_response(id, result)
      message = Message.new(id: id, result: result)
      @transport.send_message(message)
    end
    
    def send_error_response(id, error)
      message = Message.new(id: id, error: error.to_hash)
      @transport.send_message(message)
    end
    
    def send_notification(method, params = nil)
      message = Message.new(method: method, params: params)
      @transport.send_message(message)
    end
    
    def check_initialized
      raise MCPError.new("Server not initialized", ErrorCodes::INVALID_REQUEST) unless @initialized
    end
    
    def next_request_id
      @request_id += 1
    end
  end
  
  # MCP Client
  class Client
    attr_reader :server_info, :capabilities
    
    def initialize
      @transport = nil
      @logger = Logger.new(STDERR)
      @logger.level = Logger::INFO
      @request_id = 0
      @pending_requests = {}
      @initialized = false
    end
    
    def set_transport(transport)
      @transport = transport
    end
    
    def initialize_session(client_info = {})
      raise "No transport set" unless @transport
      
      params = {
        protocolVersion: PROTOCOL_VERSION,
        clientInfo: client_info.merge(name: "MCP Ruby Client", version: VERSION),
        capabilities: {
          roots: { listChanged: true },
          sampling: {}
        }
      }
      
      response = send_request(Methods::INITIALIZE, params)
      
      @server_info = response["serverInfo"]
      @capabilities = response["capabilities"]
      @initialized = true
      
      @logger.info("Connected to server: #{@server_info["name"]} v#{@server_info["version"]}")
      
      response
    end
    
    def list_tools
      check_initialized
      send_request(Methods::LIST_TOOLS)
    end
    
    def call_tool(name, arguments = {})
      check_initialized
      send_request(Methods::CALL_TOOL, { name: name, arguments: arguments })
    end
    
    def list_resources
      check_initialized
      send_request(Methods::LIST_RESOURCES)
    end
    
    def read_resource(uri)
      check_initialized
      send_request(Methods::READ_RESOURCE, { uri: uri })
    end
    
    def list_prompts
      check_initialized
      send_request(Methods::LIST_PROMPTS)
    end
    
    def get_prompt(name, arguments = {})
      check_initialized
      send_request(Methods::GET_PROMPT, { name: name, arguments: arguments })
    end
    
    def set_log_level(level)
      send_request(Methods::SET_LOG_LEVEL, { level: level })
    end
    
    def close
      @transport&.close
    end
    
    private
    
    def send_request(method, params = nil)
      id = next_request_id
      message = Message.new(id: id, method: method, params: params)
      
      @transport.send_message(message)
      
      # Wait for response
      loop do
        response = @transport.receive_message
        next unless response
        
        if response.id == id
          if response.error
            raise MCPError.new(response.error["message"], response.error["code"], response.error["data"])
          end
          return response.result
        end
      end
    end
    
    def next_request_id
      @request_id += 1
    end
    
    def check_initialized
      raise MCPError.new("Client not initialized", ErrorCodes::INVALID_REQUEST) unless @initialized
    end
  end
end

# Claude Integration Setup and Examples

# Example 1: Basic MCP Server for Claude
def create_claude_server
  server = MCP::Server.new("Ruby MCP Server for Claude", "1.0.0")
  
  # File system tool - read files
  file_reader_tool = MCP::Tool.new(
    "read_file",
    "Read contents of a file from the filesystem",
    {
      type: "object",
      properties: {
        path: { type: "string", description: "File path to read" }
      },
      required: ["path"]
    }
  )
  
  server.add_tool(file_reader_tool) do |args|
    path = args["path"]
    raise "Path required" unless path
    
    begin
      File.read(path)
    rescue => e
      "Error reading file: #{e.message}"
    end
  end
  
  # Directory listing tool
  list_dir_tool = MCP::Tool.new(
    "list_directory",
    "List contents of a directory",
    {
      type: "object",
      properties: {
        path: { type: "string", description: "Directory path to list" }
      },
      required: ["path"]
    }
  )
  
  server.add_tool(list_dir_tool) do |args|
    path = args["path"] || "."
    
    begin
      entries = Dir.entries(path).reject { |e| e == "." || e == ".." }
      entries.map { |entry|
        full_path = File.join(path, entry)
        type = File.directory?(full_path) ? "directory" : "file"
        "#{type}: #{entry}"
      }.join("\n")
    rescue => e
      "Error listing directory: #{e.message}"
    end
  end
  
  # System info tool
  system_info_tool = MCP::Tool.new(
    "system_info",
    "Get system information",
    {
      type: "object",
      properties: {}
    }
  )
  
  server.add_tool(system_info_tool) do |args|
    {
      ruby_version: RUBY_VERSION,
      platform: RUBY_PLATFORM,
      pid: Process.pid,
      working_directory: Dir.pwd,
      timestamp: Time.now.to_s
    }.map { |k, v| "#{k}: #{v}" }.join("\n")
  end
  
  # Web scraping tool (simple)
  require 'net/http'
  require 'uri'
  
  web_fetch_tool = MCP::Tool.new(
    "fetch_url",
    "Fetch content from a URL",
    {
      type: "object",
      properties: {
        url: { type: "string", description: "URL to fetch" }
      },
      required: ["url"]
    }
  )
  
  server.add_tool(web_fetch_tool) do |args|
    url = args["url"]
    raise "URL required" unless url
    
    begin
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)
      
      if response.code.to_i == 200
        response.body
      else
        "HTTP Error: #{response.code} #{response.message}"
      end
    rescue => e
      "Error fetching URL: #{e.message}"
    end
  end
  
  server
end

# Example 2: Configuration file for Claude Desktop
def generate_claude_config
  config = {
    "mcpServers" => {
      "ruby-mcp-server" => {
        "command" => "ruby",
        "args" => [File.absolute_path(__FILE__)],
        "env" => {}
      }
    }
  }
  
  puts "Add this to your Claude Desktop configuration:"
  puts "Location: ~/Library/Application Support/Claude/claude_desktop_config.json (macOS)"
  puts "Location: %APPDATA%/Claude/claude_desktop_config.json (Windows)"
  puts ""
  puts JSON.pretty_generate(config)
end

# Example 3: Standalone server script
def run_mcp_server
  server = create_claude_server
  
  # Use stdio transport for Claude integration
  transport = MCP::StdioTransport.new
  server.set_transport(transport)
  
  # Log to stderr so it doesn't interfere with MCP protocol on stdout
  STDERR.puts "MCP Ruby Server v#{MCP::VERSION} starting..."
  STDERR.puts "Server: #{server.name} v#{server.version}"
  STDERR.puts "Ready for Claude connection via stdio"
  
  # Run the server
  server.run
end

# Example 4: Advanced server with database integration
def create_advanced_server
  server = MCP::Server.new("Advanced Ruby MCP Server", "1.0.0")
  
  # SQLite integration (if sqlite3 gem is available)
  begin
    require 'sqlite3'
    
    sql_query_tool = MCP::Tool.new(
      "sql_query",
      "Execute SQL query on SQLite database",
      {
        type: "object",
        properties: {
          database: { type: "string", description: "Database file path" },
          query: { type: "string", description: "SQL query to execute" }
        },
        required: ["database", "query"]
      }
    )
    
    server.add_tool(sql_query_tool) do |args|
      db_path = args["database"]
      query = args["query"]
      
      begin
        db = SQLite3::Database.new(db_path)
        db.results_as_hash = true
        
        results = db.execute(query)
        
        if results.empty?
          "Query executed successfully. No results returned."
        else
          # Format results as a table
          headers = results.first.keys
          rows = results.map { |row| headers.map { |h| row[h] } }
          
          # Simple table formatting
          [headers.join(" | ")] + rows.map { |row| row.join(" | ") }
        end.join("\n")
      rescue => e
        "SQL Error: #{e.message}"
      ensure
        db&.close
      end
    end
    
  rescue LoadError
    # SQLite3 not available, skip this tool
  end
  
  # JSON file processor
  json_tool = MCP::Tool.new(
    "process_json",
    "Read and process JSON files",
    {
      type: "object",
      properties: {
        file_path: { type: "string", description: "Path to JSON file" },
        query: { type: "string", description: "JSONPath-like query (optional)" }
      },
      required: ["file_path"]
    }
  )
  
  server.add_tool(json_tool) do |args|
    file_path = args["file_path"]
    
    begin
      content = File.read(file_path)
      data = JSON.parse(content)
      
      # Simple query support
      if args["query"]
        # Basic dot notation support
        keys = args["query"].split(".")
        result = keys.reduce(data) { |obj, key| obj[key] if obj }
        result.nil? ? "Query returned no results" : JSON.pretty_generate(result)
      else
        JSON.pretty_generate(data)
      end
    rescue => e
      "Error processing JSON: #{e.message}"
    end
  end
  
  server
end

# Main execution
if __FILE__ == $0
  case ARGV[0]
  when "config"
    generate_claude_config
  when "advanced"
    server = create_advanced_server
    transport = MCP::StdioTransport.new
    server.set_transport(transport)
    server.run
  else
    # Default: run basic server
    run_mcp_server
  end
end