# Model Context Protocol (MCP) Implementation for Ruby 2.4
# This implementation supports multiple transport protocols and is compatible with MCP clients

require 'json'
require 'socket'
require 'uri'
require 'net/http'
require 'logger'

# Base MCP Server implementation
class MCPServer
  VERSION = '1.0.0'
  PROTOCOL_VERSION = '2024-11-05'
  
  attr_reader :name, :version, :capabilities, :transports, :logger
  
  def initialize(name:, version: '1.0.0')
    @name = name
    @version = version
    @capabilities = {
      resources: {},
      tools: {},
      prompts: {},
      logging: {}
    }
    @transports = {}
    @resources = {}
    @tools = {}
    @prompts = {}
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
  end
  
  # Resource management
  def add_resource(uri, name: nil, description: nil, mime_type: 'text/plain', &block)
    @resources[uri] = {
      uri: uri,
      name: name || uri,
      description: description,
      mime_type: mime_type,
      handler: block
    }
    @capabilities[:resources] = { list_changed: true }
  end
  
  # Tool management
  def add_tool(name, description: nil, input_schema: {}, &block)
    @tools[name] = {
      name: name,
      description: description,
      input_schema: input_schema.merge(type: 'object'),
      handler: block
    }
    @capabilities[:tools] = { list_changed: true }
  end
  
  # Prompt management
  def add_prompt(name, description: nil, arguments: [], &block)
    @prompts[name] = {
      name: name,
      description: description,
      arguments: arguments,
      handler: block
    }
    @capabilities[:prompts] = { list_changed: true }
  end
  
  # Transport registration
  def add_transport(name, transport)
    @transports[name] = transport
    transport.server = self
  end
  
  # Start all transports
  def start
    @logger.info "Starting MCP Server: #{@name} v#{@version}"
    @transports.each do |name, transport|
      @logger.info "Starting transport: #{name}"
      transport.start
    end
  end
  
  # Stop all transports
  def stop
    @logger.info "Stopping MCP Server"
    @transports.each do |name, transport|
      @logger.info "Stopping transport: #{name}"
      transport.stop
    end
  end
  
  # Handle incoming messages
  def handle_message(message, transport)
    begin
      request = JSON.parse(message)
      response = process_request(request)
      transport.send_response(response)
    rescue JSON::ParserError => e
      error_response = {
        jsonrpc: '2.0',
        id: nil,
        error: {
          code: -32700,
          message: 'Parse error',
          data: e.message
        }
      }
      transport.send_response(error_response)
    rescue => e
      @logger.error "Error handling message: #{e.message}"
      error_response = {
        jsonrpc: '2.0',
        id: request&.dig('id'),
        error: {
          code: -32603,
          message: 'Internal error',
          data: e.message
        }
      }
      transport.send_response(error_response)
    end
  end
  
  private
  
  def process_request(request)
    method = request['method']
    params = request['params'] || {}
    id = request['id']
    
    case method
    when 'initialize'
      handle_initialize(params, id)
    when 'resources/list'
      handle_resources_list(id)
    when 'resources/read'
      handle_resources_read(params, id)
    when 'tools/list'
      handle_tools_list(id)
    when 'tools/call'
      handle_tools_call(params, id)
    when 'prompts/list'
      handle_prompts_list(id)
    when 'prompts/get'
      handle_prompts_get(params, id)
    when 'ping'
      handle_ping(id)
    else
      {
        jsonrpc: '2.0',
        id: id,
        error: {
          code: -32601,
          message: 'Method not found',
          data: "Unknown method: #{method}"
        }
      }
    end
  end
  
  def handle_initialize(params, id)
    {
      jsonrpc: '2.0',
      id: id,
      result: {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: @capabilities,
        serverInfo: {
          name: @name,
          version: @version
        }
      }
    }
  end
  
  def handle_resources_list(id)
    resources = @resources.values.map do |resource|
      {
        uri: resource[:uri],
        name: resource[:name],
        description: resource[:description],
        mimeType: resource[:mime_type]
      }
    end
    
    {
      jsonrpc: '2.0',
      id: id,
      result: { resources: resources }
    }
  end
  
  def handle_resources_read(params, id)
    uri = params['uri']
    resource = @resources[uri]
    
    unless resource
      return {
        jsonrpc: '2.0',
        id: id,
        error: {
          code: -32602,
          message: 'Invalid params',
          data: "Resource not found: #{uri}"
        }
      }
    end
    
    content = resource[:handler].call if resource[:handler]
    
    {
      jsonrpc: '2.0',
      id: id,
      result: {
        contents: [{
          uri: uri,
          mimeType: resource[:mime_type],
          text: content.to_s
        }]
      }
    }
  end
  
  def handle_tools_list(id)
    tools = @tools.values.map do |tool|
      {
        name: tool[:name],
        description: tool[:description],
        inputSchema: tool[:input_schema]
      }
    end
    
    {
      jsonrpc: '2.0',
      id: id,
      result: { tools: tools }
    }
  end
  
  def handle_tools_call(params, id)
    name = params['name']
    arguments = params['arguments'] || {}
    tool = @tools[name]
    
    unless tool
      return {
        jsonrpc: '2.0',
        id: id,
        error: {
          code: -32602,
          message: 'Invalid params',
          data: "Tool not found: #{name}"
        }
      }
    end
    
    result = tool[:handler].call(arguments) if tool[:handler]
    
    {
      jsonrpc: '2.0',
      id: id,
      result: {
        content: [{
          type: 'text',
          text: result.to_s
        }]
      }
    }
  end
  
  def handle_prompts_list(id)
    prompts = @prompts.values.map do |prompt|
      {
        name: prompt[:name],
        description: prompt[:description],
        arguments: prompt[:arguments]
      }
    end
    
    {
      jsonrpc: '2.0',
      id: id,
      result: { prompts: prompts }
    }
  end
  
  def handle_prompts_get(params, id)
    name = params['name']
    arguments = params['arguments'] || {}
    prompt = @prompts[name]
    
    unless prompt
      return {
        jsonrpc: '2.0',
        id: id,
        error: {
          code: -32602,
          message: 'Invalid params',
          data: "Prompt not found: #{name}"
        }
      }
    end
    
    messages = prompt[:handler].call(arguments) if prompt[:handler]
    
    {
      jsonrpc: '2.0',
      id: id,
      result: {
        description: prompt[:description],
        messages: Array(messages).map { |msg|
          {
            role: msg[:role] || 'user',
            content: {
              type: 'text',
              text: msg[:content] || msg[:text] || msg.to_s
            }
          }
        }
      }
    }
  end
  
  def handle_ping(id)
    {
      jsonrpc: '2.0',
      id: id,
      result: {}
    }
  end
end

# Base Transport class
class Transport
  attr_accessor :server
  
  def initialize
    @server = nil
    @running = false
  end
  
  def start
    @running = true
  end
  
  def stop
    @running = false
  end
  
  def running?
    @running
  end
  
  def send_response(response)
    raise NotImplementedError, "Subclasses must implement send_response"
  end
end

# STDIO Transport (for command-line usage)
class StdioTransport < Transport
  def initialize
    super
    @input_thread = nil
  end
  
  def start
    super
    @input_thread = Thread.new do
      while running?
        begin
          line = STDIN.gets
          break unless line
          @server.handle_message(line.strip, self) if @server
        rescue => e
          @server.logger.error "STDIO transport error: #{e.message}" if @server
        end
      end
    end
  end
  
  def stop
    super
    @input_thread.kill if @input_thread
  end
  
  def send_response(response)
    STDOUT.puts JSON.generate(response)
    STDOUT.flush
  end
end

# TCP Socket Transport
class TCPTransport < Transport
  def initialize(host: 'localhost', port: 8080)
    super()
    @host = host
    @port = port
    @server_socket = nil
    @client_sockets = []
    @accept_thread = nil
  end
  
  def start
    super
    @server_socket = TCPServer.new(@host, @port)
    @accept_thread = Thread.new do
      while running?
        begin
          client = @server_socket.accept
          @client_sockets << client
          handle_client(client)
        rescue => e
          @server.logger.error "TCP transport error: #{e.message}" if @server
        end
      end
    end
    @server.logger.info "TCP transport listening on #{@host}:#{@port}" if @server
  end
  
  def stop
    super
    @server_socket.close if @server_socket
    @client_sockets.each(&:close)
    @accept_thread.kill if @accept_thread
  end
  
  def send_response(response)
    message = JSON.generate(response) + "\n"
    @client_sockets.each do |socket|
      begin
        socket.write(message)
      rescue
        @client_sockets.delete(socket)
      end
    end
  end
  
  private
  
  def handle_client(client)
    Thread.new do
      while running? && !client.closed?
        begin
          line = client.gets
          break unless line
          @server.handle_message(line.strip, self) if @server
        rescue => e
          @server.logger.error "Client error: #{e.message}" if @server
          break
        end
      end
      client.close unless client.closed?
      @client_sockets.delete(client)
    end
  end
end

# HTTP Transport (RESTful interface)
class HTTPTransport < Transport
  def initialize(host: 'localhost', port: 8080, path: '/mcp')
    super()
    @host = host
    @port = port
    @path = path
    @server_socket = nil
    @accept_thread = nil
  end
  
  def start
    super
    @server_socket = TCPServer.new(@host, @port)
    @accept_thread = Thread.new do
      while running?
        begin
          client = @server_socket.accept
          handle_http_request(client)
        rescue => e
          @server.logger.error "HTTP transport error: #{e.message}" if @server
        end
      end
    end
    @server.logger.info "HTTP transport listening on http://#{@host}:#{@port}#{@path}" if @server
  end
  
  def stop
    super
    @server_socket.close if @server_socket
    @accept_thread.kill if @accept_thread
  end
  
  def send_response(response)
    @current_response = response
  end
  
  private
  
  def handle_http_request(client)
    Thread.new do
      begin
        request_line = client.gets
        return unless request_line
        
        method, path, version = request_line.split
        headers = {}
        
        # Read headers
        while (line = client.gets.strip) != ""
          key, value = line.split(': ', 2)
          headers[key.downcase] = value
        end
        
        # Read body if present
        body = ""
        if headers['content-length']
          content_length = headers['content-length'].to_i
          body = client.read(content_length)
        end
        
        if method == 'POST' && path == @path
          @server.handle_message(body, self) if @server
          
          response_body = JSON.generate(@current_response || {})
          response = "HTTP/1.1 200 OK\r\n"
          response += "Content-Type: application/json\r\n"
          response += "Content-Length: #{response_body.length}\r\n"
          response += "Access-Control-Allow-Origin: *\r\n"
          response += "\r\n"
          response += response_body
          
          client.write(response)
        else
          # Handle OPTIONS for CORS
          if method == 'OPTIONS'
            response = "HTTP/1.1 200 OK\r\n"
            response += "Access-Control-Allow-Origin: *\r\n"
            response += "Access-Control-Allow-Methods: POST, OPTIONS\r\n"
            response += "Access-Control-Allow-Headers: Content-Type\r\n"
            response += "\r\n"
          else
            response = "HTTP/1.1 404 Not Found\r\n"
            response += "Content-Length: 0\r\n"
            response += "\r\n"
          end
          client.write(response)
        end
      rescue => e
        @server.logger.error "HTTP request error: #{e.message}" if @server
      ensure
        client.close unless client.closed?
      end
    end
  end
end

# WebSocket Transport (basic implementation)
class WebSocketTransport < Transport
  def initialize(host: 'localhost', port: 8080, path: '/ws')
    super()
    @host = host
    @port = port
    @path = path
    @server_socket = nil
    @clients = []
    @accept_thread = nil
  end
  
  def start
    super
    @server_socket = TCPServer.new(@host, @port)
    @accept_thread = Thread.new do
      while running?
        begin
          client = @server_socket.accept
          handle_websocket_handshake(client)
        rescue => e
          @server.logger.error "WebSocket transport error: #{e.message}" if @server
        end
      end
    end
    @server.logger.info "WebSocket transport listening on ws://#{@host}:#{@port}#{@path}" if @server
  end
  
  def stop
    super
    @clients.each(&:close)
    @server_socket.close if @server_socket
    @accept_thread.kill if @accept_thread
  end
  
  def send_response(response)
    message = JSON.generate(response)
    @clients.each do |client|
      begin
        send_websocket_frame(client, message)
      rescue
        @clients.delete(client)
      end
    end
  end
  
  private
  
  def handle_websocket_handshake(client)
    Thread.new do
      begin
        request_line = client.gets
        headers = {}
        
        while (line = client.gets.strip) != ""
          key, value = line.split(': ', 2)
          headers[key.downcase] = value
        end
        
        if headers['upgrade'] == 'websocket'
          key = headers['sec-websocket-key']
          accept_key = generate_websocket_accept_key(key)
          
          response = "HTTP/1.1 101 Switching Protocols\r\n"
          response += "Upgrade: websocket\r\n"
          response += "Connection: Upgrade\r\n"
          response += "Sec-WebSocket-Accept: #{accept_key}\r\n"
          response += "\r\n"
          
          client.write(response)
          @clients << client
          
          handle_websocket_messages(client)
        else
          client.close
        end
      rescue => e
        @server.logger.error "WebSocket handshake error: #{e.message}" if @server
        client.close unless client.closed?
      end
    end
  end
  
  def handle_websocket_messages(client)
    while running? && !client.closed?
      begin
        frame = read_websocket_frame(client)
        next unless frame
        @server.handle_message(frame, self) if @server
      rescue => e
        @server.logger.error "WebSocket message error: #{e.message}" if @server
        break
      end
    end
    client.close unless client.closed?
    @clients.delete(client)
  end
  
  def generate_websocket_accept_key(key)
    require 'digest/sha1'
    require 'base64'
    magic_string = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    Base64.encode64(Digest::SHA1.digest(key + magic_string)).strip
  end
  
  def read_websocket_frame(client)
    first_byte = client.read(1)
    return nil unless first_byte
    
    second_byte = client.read(1)
    return nil unless second_byte
    
    payload_length = second_byte.unpack('C')[0] & 0x7F
    
    if payload_length == 126
      length_bytes = client.read(2)
      payload_length = length_bytes.unpack('n')[0]
    elsif payload_length == 127
      length_bytes = client.read(8)
      payload_length = length_bytes.unpack('Q>')[0]
    end
    
    mask_key = client.read(4)
    payload = client.read(payload_length)
    
    # Unmask payload
    unmasked = ""
    payload.each_byte.with_index do |byte, i|
      unmasked += (byte ^ mask_key.bytes[i % 4]).chr
    end
    
    unmasked
  end
  
  def send_websocket_frame(client, message)
    frame = "\x81" # Text frame, final fragment
    
    if message.length < 126
      frame += [message.length].pack('C')
    elsif message.length < 65536
      frame += [126, message.length].pack('Cn')
    else
      frame += [127, message.length].pack('CQ>')
    end
    
    frame += message
    client.write(frame)
  end
end

# Example usage and server setup
if __FILE__ == $0
  # Create MCP server
  server = MCPServer.new(name: "Ruby MCP Server", version: "1.0.0")
  
  # Add some example resources
  server.add_resource("file://example.txt", 
                     name: "Example File", 
                     description: "An example text file") do
    "This is example content from a resource."
  end
  
  server.add_resource("config://settings", 
                     name: "Server Settings", 
                     description: "Current server configuration",
                     mime_type: "application/json") do
    JSON.generate({
      name: server.name,
      version: server.version,
      uptime: Time.now - @start_time || 0
    })
  end
  
  # Add some example tools
  server.add_tool("echo", 
                 description: "Echo back the input text",
                 input_schema: {
                   properties: {
                     text: { type: "string", description: "Text to echo back" }
                   },
                   required: ["text"]
                 }) do |args|
    "Echo: #{args['text']}"
  end
  
  server.add_tool("calculate", 
                 description: "Perform basic arithmetic calculations",
                 input_schema: {
                   properties: {
                     expression: { type: "string", description: "Mathematical expression to evaluate" }
                   },
                   required: ["expression"]
                 }) do |args|
    begin
      # Simple calculator (be careful with eval in production!)
      result = eval(args['expression'].gsub(/[^0-9+\-*\/\(\). ]/, ''))
      "Result: #{result}"
    rescue => e
      "Error: #{e.message}"
    end
  end
  
  # Add some example prompts
  server.add_prompt("greeting", 
                   description: "Generate a greeting message",
                   arguments: [
                     { name: "name", description: "Name to greet", required: false }
                   ]) do |args|
    name = args["name"] || "there"
    [
      { role: "user", content: "Generate a friendly greeting." },
      { role: "assistant", content: "Hello #{name}! How can I help you today?" }
    ]
  end
  
  # Set up transports based on command line arguments
  transport_type = ARGV[0] || 'stdio'
  
  case transport_type
  when 'stdio'
    server.add_transport('stdio', StdioTransport.new)
  when 'tcp'
    port = (ARGV[1] || 8080).to_i
    server.add_transport('tcp', TCPTransport.new(port: port))
  when 'http'
    port = (ARGV[1] || 8080).to_i
    server.add_transport('http', HTTPTransport.new(port: port))
  when 'websocket'
    port = (ARGV[1] || 8080).to_i
    server.add_transport('websocket', WebSocketTransport.new(port: port))
  when 'all'
    server.add_transport('tcp', TCPTransport.new(port: 8080))
    server.add_transport('http', HTTPTransport.new(port: 8081))
    server.add_transport('websocket', WebSocketTransport.new(port: 8082))
  else
    puts "Usage: ruby #{$0} [stdio|tcp|http|websocket|all] [port]"
    exit 1
  end
  
  # Start the server
  @start_time = Time.now
  
  begin
    server.start
    
    # Keep the main thread alive
    if transport_type == 'stdio'
      # For STDIO, wait for input thread to finish
      sleep
    else
      # For network transports, handle shutdown gracefully
      trap('INT') do
        server.logger.info "Shutting down..."
        server.stop
        exit 0
      end
      
      sleep
    end
  rescue Interrupt
    server.logger.info "Shutting down..."
    server.stop
  end
end