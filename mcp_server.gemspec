# mcp_server.gemspec for Ruby package
Gem::Specification.new do |spec|
  spec.name          = "mcp_server"
  spec.version       = "1.0.0"
  spec.authors       = ["Rahul Ghuge"]
  spec.email         = ["1994ghuge@gmail.com"]

  spec.summary       = "Model Context Protocol (MCP) implementation in Ruby 2.4.xx."
  spec.description   = "A Ruby gem implementing the Model Context Protocol (MCP)."
  spec.homepage      = "https://github.com/Rahulghuge94/mcp_server"
  spec.license       = "Apache-2.0"

  spec.files         = Dir["lib/**/*.rb"] + ["README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.4.0"
end
