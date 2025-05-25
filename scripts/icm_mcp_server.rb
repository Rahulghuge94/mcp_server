require_relative 'mcp_server'  # Assuming mcp_server.rb is in the same directory

$db = nil
$net = nil

# Example MCP Server
server = MCP::Server.new("ICM MCP Server", "1.0.0")

# Add a tool to open an ICM database using InfoWorks Ruby API
open_db_tool = MCP::Tool.new(
  "open_icm_database",
  "Opens an InfoWorks ICM database using WSApplication.open. Returns error if fails.",
  {
    type: "object",
    properties: {
      dbname: { type: ["string", "null"], description: "Database name or nil for to load open database in ICM user iterface." }
    },
    required: []
  }
)

server.add_tool(open_db_tool) do |args|
  begin
    dbname = args["dbname"]
    if dbname.nil? || dbname.to_s.strip.empty?
      $db = WSApplication.open
    else
      $db = WSApplication.open(dbname)
    end
    { status: 'success', message: "Database opened", dbname: dbname }
  rescue => e
    { status: 'error', message: e.message }
  end
end

# Add a tool to open a network in the currently open ICM database
open_network_tool = MCP::Tool.new(
  "open_icm_network",
  "Opens a network in the currently open InfoWorks ICM database using model_object_from_type_and_id. Requires network id (integer). Returns error if fails or if database is not open.",
  {
    type: "object",
    properties: {
      id: { type: "integer", description: "Network ID (integer)" },
      # type: { type: "string", description: "Model Object type (string)" },
      dbname: { type: "string", description: "Database name from which to open network (string)" }
    },
    required: ["id"]
  }
)

server.add_tool(open_network_tool) do |args|
  begin
    if $db.nil? and args["dbname"].nil?
      raise "No database is open. Please open a database first."
    end

    if !args["dbname"].nil?
      $db = WSApplication.Open(args["dbname"])
      if $db.nil?
        raise "Database with name '#{args["dbname"]}' not found."
      end
    end

    id = args["id"]
    $net = $db.model_object_from_type_and_id("Model Network", id)
    if $net.nil?
      { status: 'error', message: "Network with id #{id} not found." }
    else
      { status: 'success', message: "Network opened", id: id, name: $net.name }
    end
  rescue => e
    { status: 'error', message: e.message }
  end
end

# Set up stdio transport and run
transport = MCP::StdioTransport.new
server.set_transport(transport)
puts "MCP Ruby Server v#{MCP::VERSION} ready on stdio"
puts "Protocol version: #{MCP::PROTOCOL_VERSION}"

server.run  # Uncomment to run the server

# if __FILE__ == $0
#   # Example MCP Server
#   server = MCP::Server.new("ICM MCP Server", "1.0.0")
  
#   # Add a simple calculator tool
#   calc_tool = MCP::Tool.new(
#     "calculator",
#     "Performs basic arithmetic operations",
#     {
#       type: "object",
#       properties: {
#         operation: { type: "string", enum: ["add", "subtract", "multiply", "divide"] },
#         a: { type: "number" },
#         b: { type: "number" }
#       },
#       required: ["operation", "a", "b"]
#     }
#   )
  
#   server.add_tool(calc_tool) do |args|
#     a = args["a"].to_f
#     b = args["b"].to_f
    
#     case args["operation"]
#     when "add"
#       a + b
#     when "subtract"
#       a - b
#     when "multiply"
#       a * b
#     when "divide"
#       raise "Division by zero" if b == 0
#       a / b
#     else
#       raise "Unknown operation: #{args["operation"]}"
#     end
#   end
  
#   # Add a file resource
#   file_resource = MCP::Resource.new(
#     "file:///example.txt",
#     "Example File",
#     "A simple text file resource",
#     "text/plain"
#   )
  
#   server.add_resource(file_resource) do |uri|
#     "This is the content of the example file at #{uri}"
#   end
  
#   # Add a greeting prompt
#   greeting_prompt = MCP::Prompt.new(
#     "greeting",
#     "Generate a personalized greeting",
#     [
#       { name: "name", description: "The person's name", required: true }
#     ]
#   )
  
#   server.add_prompt(greeting_prompt) do |args|
#     name = args["name"] || "World"
#     "Hello, #{name}! Welcome to the MCP Ruby implementation."
#   end
  
  
#   # Set up stdio transport and run
#   transport = MCP::StdioTransport.new
#   server.set_transport(transport)
  
#   puts "MCP Ruby Server v#{MCP::VERSION} ready on stdio"
#   puts "Protocol version: #{MCP::PROTOCOL_VERSION}"
  
#   server.run  # Uncomment to run the server
# end
