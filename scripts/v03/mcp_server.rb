#!/usr/bin/env ruby
# Universal Model Context Protocol (MCP) Server
# Compatible with Claude, VS Code Copilot, OpenAI, Anthropic, and other AI agents

require 'json'
require 'socket'
require 'logger'
require 'uri'
require 'webrick'
require 'net/http'
require 'optparse'

module UniversalMCP
  VERSION = "2.0.0"
  PROTOCOL_VERSION = "2024-11-05"
  
  # Configuration for different AI agents
  class AgentConfig
    CLAUDE = {
      name: "Claude",
      transport: :stdio,
      message_format: :jsonrpc,
      capabilities: [:tools, :resources, :prompts]
    }
    
    COPILOT = {
      name: "VS Code Copilot",
      transport: :http,
      message_format: :openai,
      capabilities: [:tools, :functions]
    }
    
    OPENAI = {
      name: "OpenAI",
      transport: :http,
      message_format: :openai,
      capabilities: [:tools, :functions]
    }
    
    ANTHROPIC = {
      name: "Anthropic API",
      transport: :http,
      message_format: :anthropic,
      capabilities: [:tools]
    }
    
    GENERIC = {
      name: "Generic Agent",
      transport: :auto,
      message_format: :auto,
      capabilities: [:tools, :resources, :prompts]
    }
  end
  
  # Universal message format that can adapt to different protocols
  class UniversalMessage
    attr_accessor :id, :method, :params, :result, :error, :format
    
    def initialize(id: nil, method: nil, params: nil, result: nil, error: nil, format: :jsonrpc)
      @id = id
      @method = method
      @params = params
      @result = result
      @error = error
      @format = format
    end
    
    def to_mcp_format
      hash = { jsonrpc: "2.0" }
      hash[:id] = @id if @id
      hash[:method] = @method if @method
      hash[:params] = @params if @params
      hash[:result] = @result if @result
      hash[:error] = @error if @error
      hash
    end
    
    def to_openai_format
      case @method
      when "tools/call"
        {
          type: "function",
          function: {
            name: @params["name"],
            arguments: JSON.generate(@params["arguments"] || {})
          }
        }
      else
        to_mcp_format
      end
    end
    
    def to_anthropic_format
      case @method
      when "tools/call"
        {
          type: "tool_use",
          id: @id,
          name: @params["name"],
          input: @params["arguments"] || {}
        }
      else
        to_mcp_format
      end
    end
    
    def to_format(target_format)
      case target_format
      when :jsonrpc, :mcp
        to_mcp_format
      when :openai
        to_openai_format
      when :anthropic
        to_anthropic_format
      else
        to_mcp_format
      end
    end
    
    def to_json(target_format = @format)
      JSON.generate(to_format(target_format))
    end
    
    def self.from_openai(data)
      if data["function_call"]
        new(
          id: data["id"],
          method: "tools/call",
          params: {
            "name" => data["function_call"]["name"],
            "arguments" => JSON.parse(data["function_call"]["arguments"] || "{}")
          },
          format: :openai
        )
      else
        from_generic(data)
      end
    end
    
    def self.from_anthropic(data)
      if data["type"] == "tool_use"
        new(
          id: data["id"],
          method: "tools/call", 
          params: {
            "name" => data["name"],
            "arguments" => data["input"] || {}
          },
          format: :anthropic
        )
      else
        from_generic(data)
      end
    end
    
    def self.from_generic(data)
      new(
        id: data["id"],
        method: data["method"],
        params: data["params"],
        result: data["result"],
        error: data["error"],
        format: :jsonrpc
      )
    end
    
    def self.auto_detect_and_parse(json_str)
      data = JSON.parse(json_str)
      
      # Detect format based on structure
      if data["function_call"] || data["functions"]
        from_openai(data)
      elsif data["type"] == "tool_use"
        from_anthropic(data)
      else
        from_generic(data)
      end
    rescue JSON::ParserError => e
      raise MCPError.new("Parse error: #{e.message}", -32700)
    end
  end
  
  # HTTP Transport for REST APIs and webhooks
  class HTTPTransport
    def initialize(port = 8080, host = "localhost")
      @port = port
      @host = host
      @server = nil
      @logger = Logger.new(STDERR)
      @message_queue = []
      @response_handlers = {}
    end
    
    def start_server(&message_handler)
      @server = WEBrick::HTTPServer.new(
        Port: @port,
        Host: @host,
        Logger: WEBrick::Log.new("/dev/null"),
        AccessLog: []
      )
      
      # Handle MCP requests
      @server.mount_proc '/mcp' do |req, res|
        begin
          if req.request_method == 'POST'
            body = req.body
            message = UniversalMessage.auto_detect_and_parse(body)
            
            response = message_handler.call(message) if message_handler
            
            res.status = 200
            res['Content-Type'] = 'application/json'
            res.body = response ? response.to_json : '{"status": "ok"}'
          else
            res.status = 405
            res.body = '{"error": "Method not allowed"}'
          end
        rescue => e
          @logger.error("HTTP request error: #{e.message}")
          res.status = 500
          res.body = JSON.generate({error: e.message})
        end
      end
      
      # Health check endpoint
      @server.mount_proc '/health' do |req, res|
        res.status = 200
        res['Content-Type'] = 'application/json'
        res.body = JSON.generate({
          status: "healthy",
          version: VERSION,
          protocol_version: PROTOCOL_VERSION,
          timestamp: Time.now.iso8601
        })
      end
      
      # OpenAPI/Swagger documentation
      @server.mount_proc '/openapi' do |req, res|
        res.status = 200
        res['Content-Type'] = 'application/json'
        res.body = generate_openapi_spec
      end
      
      @logger.info("HTTP MCP Server starting on #{@host}:#{@port}")
      @server.start
    end
    
    def stop_server
      @server&.shutdown
      @logger.info("HTTP server stopped")
    end
    
    def send_message(message)
      # For HTTP, we typically respond to requests rather than send unsolicited messages
      @message_queue << message
    end
    
    def receive_message
      @message_queue.shift
    end
    
    private
    
    def generate_openapi_spec
      JSON.generate({
        openapi: "3.0.0",
        info: {
          title: "Universal MCP Server",
          version: VERSION,
          description: "Model Context Protocol server compatible with multiple AI agents"
        },
        servers: [
          { url: "http://#{@host}:#{@port}", description: "Local MCP Server" }
        ],
        paths: {
          "/mcp" => {
            post: {
              summary: "Execute MCP request",
              requestBody: {
                required: true,
                content: {
                  "application/json" => {
                    schema: { type: "object" }
                  }
                }
              },
              responses: {
                "200" => {
                  description: "Successful response",
                  content: {
                    "application/json" => {
                      schema: { type: "object" }
                    }
                  }
                }
              }
            }
          },
          "/health" => {
            get: {
              summary: "Health check",
              responses: {
                "200" => {
                  description: "Server is healthy"
                }
              }
            }
          }
        }
      })
    end
  end
  
  # WebSocket Transport for real-time communication
  class WebSocketTransport
    def initialize(port = 8081)
      @port = port
      @connections = []
      @logger = Logger.new(STDERR)
    end
    
    def start_server(&message_handler)
      require 'em-websocket'
      
      EM.run do
        EM::WebSocket.run(host: "0.0.0.0", port: @port) do |ws|
          ws.onopen do |handshake|
            @logger.info("WebSocket connection opened: #{handshake.path}")
            @connections << ws
          end
          
          ws.onmessage do |msg|
            begin
              message = UniversalMessage.auto_detect_and_parse(msg)
              response = message_handler.call(message) if message_handler
              ws.send(response.to_json) if response
            rescue => e
              @logger.error("WebSocket message error: #{e.message}")
              error_response = UniversalMessage.new(error: {code: -32603, message: e.message})
              ws.send(error_response.to_json)
            end
          end
          
          ws.onclose do
            @logger.info("WebSocket connection closed")
            @connections.delete(ws)
          end
        end
        
        @logger.info("WebSocket MCP Server started on port #{@port}")
      end
    rescue LoadError
      @logger.error("EventMachine WebSocket not available. Install with: gem install em-websocket")
    end
    
    def broadcast_message(message)
      @connections.each do |ws|
        ws.send(message.to_json)
      end
    end
  end
  
  # Enhanced Universal Server
  class UniversalServer
    attr_reader :name, :version, :capabilities, :tools, :resources, :prompts
    
    def initialize(name = "Universal MCP Server", version = VERSION)
      @name = name
      @version = version
      @tools = {}
      @resources = {}
      @prompts = {}
      @functions = {} # OpenAI-style functions
      @transports = []
      @logger = Logger.new(STDERR)
      @logger.level = Logger::INFO
      @agent_configs = {}
      @middleware = []
      
      # Universal capabilities
      @capabilities = {
        tools: { listChanged: true },
        resources: { subscribe: true, listChanged: true },
        prompts: { listChanged: true },
        functions: { listChanged: true }, # For OpenAI compatibility
        experimental: {
          multiAgent: true,
          httpTransport: true,
          websocketTransport: true
        }
      }
    end
    
    # Add middleware for request/response processing
    def use_middleware(&block)
      @middleware << block
    end
    
    # Configure for specific agents
    def configure_for_agent(agent_type, config = {})
      base_config = case agent_type.to_sym
      when :claude
        AgentConfig::CLAUDE
      when :copilot, :vscode
        AgentConfig::COPILOT
      when :openai
        AgentConfig::OPENAI
      when :anthropic
        AgentConfig::ANTHROPIC
      else
        AgentConfig::GENERIC
      end
      
      @agent_configs[agent_type] = base_config.merge(config)
    end
    
    def add_tool(name, description, schema = nil, &handler)
      tool = {
        name: name,
        description: description,
        schema: schema || { type: "object", properties: {} },
        handler: handler
      }
      
      @tools[name] = tool
      
      # Also add as OpenAI function format
      @functions[name] = {
        name: name,
        description: description,
        parameters: schema || { type: "object", properties: {} }
      }
      
      @logger.info("Added tool: #{name}")
    end
    
    def add_transport(transport)
      @transports << transport
    end
    
    # Start all configured transports
    def start_all_transports
      @transports.each do |transport|
        case transport
        when HTTPTransport
          Thread.new { transport.start_server { |msg| handle_message(msg) } }
        when WebSocketTransport
          Thread.new { transport.start_server { |msg| handle_message(msg) } }
        else
          # For stdio and other transports, run in main thread
          transport_thread = Thread.new { run_transport(transport) }
        end
      end
      
      @logger.info("All transports started")
      
      # Keep main thread alive
      sleep
    end
    
    def run_transport(transport)
      loop do
        begin
          message = transport.receive_message
          break unless message
          
          response = handle_message(message)
          transport.send_message(response) if response
        rescue => e
          @logger.error("Transport error: #{e.message}")
          break
        end
      end
    end
    
    # Enhanced message handling with middleware support
    def handle_message(message)
      # Apply middleware
      @middleware.each { |middleware| message = middleware.call(message, :before) }
      
      response = case message.method
      when "initialize"
        handle_initialize(message)
      when "tools/list", "functions/list"
        handle_list_tools(message)
      when "tools/call", "function_call"
        handle_call_tool(message)
      when "resources/list"
        handle_list_resources(message)
      when "resources/read"
        handle_read_resource(message)
      when "prompts/list"
        handle_list_prompts(message)
      when "prompts/get"
        handle_get_prompt(message)
      else
        create_error_response(message.id, "Method not found: #{message.method}", -32601)
      end
      
      # Apply middleware to response
      @middleware.each { |middleware| response = middleware.call(response, :after) }
      
      response
    end
    
    private
    
    def handle_initialize(message)
      params = message.params || {}
      client_info = params["clientInfo"] || {}
      
      # Detect agent type from client info
      agent_type = detect_agent_type(client_info)
      @logger.info("Detected agent type: #{agent_type}")
      
      result = {
        protocolVersion: PROTOCOL_VERSION,
        serverInfo: {
          name: @name,
          version: @version,
          agentType: agent_type
        },
        capabilities: @capabilities
      }
      
      create_response(message.id, result)
    end
    
    def handle_list_tools(message)
      # Return tools in the format expected by the requesting agent
      tools_array = @tools.values.map do |tool|
        {
          name: tool[:name],
          description: tool[:description],
          inputSchema: tool[:schema]
        }
      end
      
      # Also include OpenAI function format
      functions_array = @functions.values
      
      result = {
        tools: tools_array,
        functions: functions_array # For OpenAI compatibility
      }
      
      create_response(message.id, result)
    end
    
    def handle_call_tool(message)
      params = message.params || {}
      tool_name = params["name"] || params["function"]&.dig("name")
      arguments = params["arguments"] || 
                 (params["function"] ? JSON.parse(params["function"]["arguments"] || "{}") : {})
      
      tool = @tools[tool_name]
      return create_error_response(message.id, "Tool not found: #{tool_name}", -32000) unless tool
      
      begin
        result = tool[:handler].call(arguments)
        
        # Format response based on the requesting agent
        formatted_result = format_tool_result(result, message.format)
        
        create_response(message.id, formatted_result)
      rescue => e
        @logger.error("Tool execution error: #{e.message}")
        create_error_response(message.id, "Tool execution failed: #{e.message}", -32603)
      end
    end
    
    def handle_list_resources(message)
      resources_array = @resources.values.map do |resource|
        {
          uri: resource[:uri],
          name: resource[:name],
          description: resource[:description],
          mimeType: resource[:mime_type]
        }.compact
      end
      
      create_response(message.id, { resources: resources_array })
    end
    
    def handle_read_resource(message)
      params = message.params || {}
      uri = params["uri"]
      
      resource = @resources[uri]
      return create_error_response(message.id, "Resource not found: #{uri}", -32001) unless resource
      
      begin
        content = resource[:handler].call(uri)
        result = {
          contents: [{
            uri: uri,
            mimeType: resource[:mime_type] || "text/plain",
            text: content.to_s
          }]
        }
        
        create_response(message.id, result)
      rescue => e
        create_error_response(message.id, "Resource read failed: #{e.message}", -32603)
      end
    end
    
    def handle_list_prompts(message)
      prompts_array = @prompts.values.map do |prompt|
        {
          name: prompt[:name],
          description: prompt[:description],
          arguments: prompt[:arguments] || []
        }.compact
      end
      
      create_response(message.id, { prompts: prompts_array })
    end
    
    def handle_get_prompt(message)
      params = message.params || {}
      prompt_name = params["name"]
      arguments = params["arguments"] || {}
      
      prompt = @prompts[prompt_name]
      return create_error_response(message.id, "Prompt not found: #{prompt_name}", -32003) unless prompt
      
      begin
        content = prompt[:handler].call(arguments)
        result = {
          description: prompt[:description],
          messages: [{
            role: "user",
            content: {
              type: "text",
              text: content.to_s
            }
          }]
        }
        
        create_response(message.id, result)
      rescue => e
        create_error_response(message.id, "Prompt generation failed: #{e.message}", -32603)
      end
    end
    
    def detect_agent_type(client_info)
      name = client_info["name"]&.downcase || ""
      
      case name
      when /claude/
        :claude
      when /copilot/, /vscode/
        :copilot
      when /openai/
        :openai
      when /anthropic/
        :anthropic
      else
        :generic
      end
    end
    
    def format_tool_result(result, format)
      case format
      when :openai
        {
          role: "function",
          name: "function_result",
          content: result.to_s
        }
      when :anthropic
        {
          type: "tool_result",
          content: [{
            type: "text",
            text: result.to_s
          }]
        }
      else
        # MCP format
        {
          content: [{
            type: "text",
            text: result.to_s
          }]
        }
      end
    end
    
    def create_response(id, result)
      UniversalMessage.new(id: id, result: result)
    end
    
    def create_error_response(id, message, code)
      UniversalMessage.new(id: id, error: { code: code, message: message })
    end
  end
  
  # Configuration generator for different agents
  class ConfigGenerator
    def self.generate_claude_config(server_path)
      {
        mcpServers: {
          "universal-mcp-server" => {
            command: "ruby",
            args: [server_path, "--mode=claude"],
            env: {}
          }
        }
      }
    end
    
    def self.generate_vscode_config(server_url)
      {
        "copilot.agent.mcp.servers": [{
          name: "universal-mcp-server",
          url: server_url,
          capabilities: ["tools", "functions"]
        }]
      }
    end
    
    def self.generate_openai_config(server_url)
      {
        functions_endpoint: server_url,
        tools_endpoint: "#{server_url}/tools",
        capabilities: ["function_calling", "tools"]
      }
    end
  end
end

# CLI Interface
def main
  options = {
    mode: :auto,
    port: 8080,
    ws_port: 8081,
    transports: [:stdio]
  }
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"
    
    opts.on("--mode MODE", "Agent mode (claude, copilot, openai, anthropic, auto)") do |mode|
      options[:mode] = mode.to_sym
    end
    
    opts.on("--transport TRANSPORT", "Transport method (stdio, http, websocket, all)") do |transport|
      options[:transports] = transport == "all" ? [:stdio, :http, :websocket] : [transport.to_sym]
    end
    
    opts.on("--port PORT", Integer, "HTTP port (default: 8080)") do |port|
      options[:port] = port
    end
    
    opts.on("--ws-port PORT", Integer, "WebSocket port (default: 8081)") do |port|
      options[:ws_port] = port
    end
    
    opts.on("--config AGENT", "Generate config for agent (claude, vscode, openai)") do |agent|
      case agent
      when "claude"
        puts JSON.pretty_generate(UniversalMCP::ConfigGenerator.generate_claude_config(__FILE__))
      when "vscode"
        puts JSON.pretty_generate(UniversalMCP::ConfigGenerator.generate_vscode_config("http://localhost:#{options[:port]}/mcp"))
      when "openai"
        puts JSON.pretty_generate(UniversalMCP::ConfigGenerator.generate_openai_config("http://localhost:#{options[:port]}"))
      end
      exit
    end
    
    opts.on("-h", "--help", "Show this help") do
      puts opts
      exit
    end
  end.parse!
  
  # Create universal server
  server = UniversalMCP::UniversalServer.new("Universal MCP Server", UniversalMCP::VERSION)
  
  # Configure for detected or specified agent
  server.configure_for_agent(options[:mode])
  
  # Add logging middleware
  server.use_middleware do |message, phase|
    if phase == :before
      STDERR.puts "[#{Time.now}] Received: #{message.method}" if message.method
    end
    message
  end
  
  # Add sample tools
  add_sample_tools(server)
  
  # Set up transports
  options[:transports].each do |transport_type|
    case transport_type
    when :stdio
      server.add_transport(MCP::StdioTransport.new)
    when :http
      server.add_transport(UniversalMCP::HTTPTransport.new(options[:port]))
    when :websocket
      server.add_transport(UniversalMCP::WebSocketTransport.new(options[:ws_port]))
    end
  end
  
  STDERR.puts "Universal MCP Server v#{UniversalMCP::VERSION} starting..."
  STDERR.puts "Mode: #{options[:mode]}"
  STDERR.puts "Transports: #{options[:transports].join(', ')}"
  
  # Start server
  if options[:transports].size > 1
    server.start_all_transports
  else
    # Single transport - run in main thread
    transport = server.instance_variable_get(:@transports).first
    case transport
    when UniversalMCP::HTTPTransport
      transport.start_server { |msg| server.handle_message(msg) }
    else
      server.run_transport(transport)
    end
  end
end

def add_sample_tools(server)
  # File operations
  server.add_tool("read_file", "Read contents of a file", {
    type: "object",
    properties: {
      path: { type: "string", description: "File path to read" }
    },
    required: ["path"]
  }) do |args|
    File.read(args["path"])
  rescue => e
    "Error: #{e.message}"
  end
  
  server.add_tool("list_directory", "List directory contents", {
    type: "object", 
    properties: {
      path: { type: "string", description: "Directory path" }
    }
  }) do |args|
    path = args["path"] || "."
    Dir.entries(path).reject { |e| e.start_with?('.') }.join("\n")
  rescue => e
    "Error: #{e.message}"
  end
  
  # System operations
  server.add_tool("system_info", "Get system information") do |args|
    {
      ruby_version: RUBY_VERSION,
      platform: RUBY_PLATFORM,
      pid: Process.pid,
      pwd: Dir.pwd,
      timestamp: Time.now.iso8601
    }.map { |k, v| "#{k}: #{v}" }.join("\n")
  end
  
  # Web operations
  server.add_tool("fetch_url", "Fetch content from URL", {
    type: "object",
    properties: {
      url: { type: "string", description: "URL to fetch" }
    },
    required: ["url"]
  }) do |args|
    uri = URI.parse(args["url"])
    Net::HTTP.get_response(uri).body
  rescue => e
    "Error: #{e.message}"
  end
end

# Run if this file is executed directly
if __FILE__ == $0
  main
end