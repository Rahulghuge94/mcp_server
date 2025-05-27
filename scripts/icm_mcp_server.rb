require_relative 'mcp_server'
require 'thread'
require 'datetime'
require 'json'

class ICMMCPServer
  def initialize
    @db = nil
    @net = nil
    @server = MCP::Server.new("ICM MCP Server", "1.0.0")
    register_tools
  end

  def register_tools

    # Tool: WSModelObject methods (Exchange only)
    wsmodelobject_tools = [
      {
        name: "mo_get_field",
        desc: "Get a field value from a model object.",
        params: {
          object: { type: "object", description: "Model object." },
          field: { type: "string", description: "Field name to get." }
        },
        required: ["object", "field"]
      },
      {
        name: "mo_set_field",
        desc: "Set a field value on a model object.",
        params: {
          object: { type: "object", description: "Model object." },
          field: { type: "string", description: "Field name to set." },
          value: { type: ["string", "number", "boolean", "object", "null"], description: "Value to set." }
        },
        required: ["object", "field", "value"]
      },
      {
        name: "mo_bulk_delete",
        desc: "Bulk delete a model object and all its children.",
        params: {
          object: { type: "object", description: "Model object to delete." }
        },
        required: ["object"]
      },
      {
        name: "mo_children",
        desc: "Get children of a model object.",
        params: {
          object: { type: "object", description: "Model object." }
        },
        required: ["object"]
      },
      {
        name: "mo_comment",
        desc: "Get the comment/description of a model object.",
        params: {
          object: { type: "object", description: "Model object." }
        },
        required: ["object"]
      },
      {
        name: "mo_set_comment",
        desc: "Set the comment/description of a model object.",
        params: {
          object: { type: "object", description: "Model object." },
          comment: { type: "string", description: "Comment to set." }
        },
        required: ["object", "comment"]
      },
      {
        name: "mo_delete",
        desc: "Delete a model object.",
        params: {
          object: { type: "object", description: "Model object to delete." }
        },
        required: ["object"]
      },
      {
        name: "mo_name",
        desc: "Get the name of a model object.",
        params: {
          object: { type: "object", description: "Model object." }
        },
        required: ["object"]
      },
      {
        name: "mo_set_name",
        desc: "Set the name of a model object.",
        params: {
          object: { type: "object", description: "Model object." },
          name: { type: "string", description: "Name to set." }
        },
        required: ["object", "name"]
      },
      {
        name: "mo_type",
        desc: "Get the scripting type of a model object.",
        params: {
          object: { type: "object", description: "Model object." }
        },
        required: ["object"]
      },
      {
        name: "mo_id",
        desc: "Get the ID of a model object.",
        params: {
          object: { type: "object", description: "Model object." }
        },
        required: ["object"]
      },
      {
        name: "mo_path",
        desc: "Get the scripting path of a model object.",
        params: {
          object: { type: "object", description: "Model object." }
        },
        required: ["object"]
      }
      # ... (add more as needed)
    ]

    wsmodelobject_tools.each do |tool|
      t = MCP::Tool.new(
        tool[:name],
        tool[:desc],
        {
          type: "object",
          properties: tool[:params],
          required: tool[:required]
        }
      )
      @server.add_tool(t) do |args|
        begin
          raise "No database is open. Please open a database first." if @db.nil?
          object = args["object"]
          case tool[:name]
          when "mo_get_field"
            field = args["field"]
            value = object[field]
            { status: 'success', value: value }
          when "mo_set_field"
            field = args["field"]
            value = args["value"]
            object[field] = value
            { status: 'success' }
          when "mo_bulk_delete"
            object.bulk_delete
            { status: 'success' }
          when "mo_children"
            children = object.children
            { status: 'success', children: children }
          when "mo_comment"
            comment = object.comment
            { status: 'success', comment: comment }
          when "mo_set_comment"
            comment = args["comment"]
            object.comment = comment
            { status: 'success' }
          when "mo_delete"
            object.delete
            { status: 'success' }
          when "mo_name"
            name = object.name
            { status: 'success', name: name }
          when "mo_set_name"
            name = args["name"]
            object.name = name
            { status: 'success' }
          when "mo_type"
            t = object.type
            { status: 'success', type: t }
          when "mo_id"
            id = object.id
            { status: 'success', id: id }
          when "mo_path"
            path = object.path
            { status: 'success', path: path }
          else
            { status: 'error', message: 'Unknown WSModelObject tool' }
          end
        rescue => e
          { status: 'error', message: e.message }
        end
      end
    end

    # Tool: WSOpenNetwork methods
    wsopen_network_tools = [
      {
        name: "add_scenario",
        desc: "Add a scenario to the open network.",
        params: {
          name: { type: "string", description: "Name of new scenario." },
          based_on: { type: ["string", "null"], description: "Name of scenario to base on, or nil." },
          notes: { type: ["string", "null"], description: "Notes for the scenario." }
        },
        required: ["name"]
      },
      {
        name: "clear_selection",
        desc: "Clear the selection in the open network.",
        params: {},
        required: []
      },
      {
        name: "csv_export",
        desc: "Export the open network to a CSV file.",
        params: {
          filename: { type: "string", description: "CSV file path to export to." },
          options: { type: ["object", "null"], description: "Options hash for export (see documentation)." }
        },
        required: ["filename"]
      },
      {
        name: "csv_import",
        desc: "Import a CSV file into the open network.",
        params: {
          filename: { type: "string", description: "CSV file path to import from." },
          options: { type: ["object", "null"], description: "Options hash for import (see documentation)." }
        },
        required: ["filename"]
      },
      {
        name: "current_scenario",
        desc: "Get the current scenario name.",
        params: {},
        required: []
      },
      {
        name: "set_current_scenario",
        desc: "Set the current scenario.",
        params: {
          scenario: { type: ["string", "null"], description: "Scenario name to set as current, or nil for base." }
        },
        required: ["scenario"]
      },
      {
        name: "delete_scenario",
        desc: "Delete a scenario from the open network.",
        params: {
          scenario_name: { type: "string", description: "Name of the scenario to delete." }
        },
        required: ["scenario_name"]
      }
      # ... (add more as needed)
    ]

    wsopen_network_tools.each do |tool|
      t = MCP::Tool.new(
        tool[:name],
        tool[:desc],
        {
          type: "object",
          properties: tool[:params],
          required: tool[:required]
        }
      )
      @server.add_tool(t) do |args|
        begin
          raise "No network is open. Please open a network first." if @net.nil?
          case tool[:name]
          when "add_scenario"
            name = args["name"]
            based_on = args["based_on"]
            notes = args["notes"]
            sc = @net.add_scenario(name, based_on, notes)
            { status: 'success', scenario: sc }
          when "clear_selection"
            @net.clear_selection
            { status: 'success' }
          when "csv_export"
            filename = args["filename"]
            options = args["options"]
            @net.csv_export(filename, options)
            { status: 'success', filename: filename }
          when "csv_import"
            filename = args["filename"]
            options = args["options"]
            @net.csv_import(filename, options)
            { status: 'success', filename: filename }
          when "current_scenario"
            cs = @net.current_scenario
            { status: 'success', current_scenario: cs }
          when "set_current_scenario"
            scenario = args["scenario"]
            @net.current_scenario = scenario
            { status: 'success', current_scenario: @net.current_scenario }
          when "delete_scenario"
            scenario_name = args["scenario_name"]
            @net.delete_scenario(scenario_name)
            { status: 'success', deleted: scenario_name }
          else
            { status: 'error', message: 'Unknown WSOpenNetwork tool' }
          end
        rescue => e
          { status: 'error', message: e.message }
        end
      end
    end

    # Tool: WSDatabase methods (Exchange only)
    wsdb_tools = [
      {
        name: "wsdb_copy_into_root",
        desc: "Copy a model object into the root of the database.",
        params: {
          object: { type: "object", description: "Model object to copy (from another database)" },
          bCopySims: { type: "boolean", description: "Copy simulation results?" },
          bCopyGroundModels: { type: "boolean", description: "Copy ground models?" }
        },
        required: ["object"]
      },
      {
        name: "wsdb_file_root",
        desc: "Get the GIS file root for the database.",
        params: {},
        required: []
      },
      {
        name: "wsdb_find_model_object",
        desc: "Find a model object by type and name.",
        params: {
          type: { type: "string", description: "Scripting type of the object." },
          name: { type: "string", description: "Name of the object." }
        },
        required: ["type", "name"]
      },
      {
        name: "wsdb_find_root_model_object",
        desc: "Find a root model object by type and name.",
        params: {
          type: { type: "string", description: "Scripting type of the object." },
          name: { type: "string", description: "Name of the object." }
        },
        required: ["type", "name"]
      },
      {
        name: "wsdb_guid",
        desc: "Get the GUID (database identifier) for the database.",
        params: {},
        required: []
      },
      {
        name: "wsdb_list_read_write_run_fields",
        desc: "List all read-write run fields (ICM only).",
        params: {},
        required: []
      },
      {
        name: "wsdb_model_object",
        desc: "Get a model object by scripting path.",
        params: {
          scripting_path: { type: "string", description: "Scripting path of the object." }
        },
        required: ["scripting_path"]
      },
      {
        name: "wsdb_model_object_collection",
        desc: "Get all model objects of a given type.",
        params: {
          type: { type: "string", description: "Scripting type of the objects." }
        },
        required: ["type"]
      },
      {
        name: "wsdb_model_object_from_type_and_guid",
        desc: "Get a model object by type and GUID.",
        params: {
          type: { type: "string", description: "Scripting type of the object." },
          guid: { type: "string", description: "CreationGUID of the object." }
        },
        required: ["type", "guid"]
      },
      {
        name: "wsdb_model_object_from_type_and_id",
        desc: "Get a model object by type and ID.",
        params: {
          type: { type: "string", description: "Scripting type of the object." },
          id: { type: "integer", description: "ID of the object." }
        },
        required: ["type", "id"]
      },
      {
        name: "wsdb_new_network_name",
        desc: "Generate a new network name.",
        params: {
          type: { type: "string", description: "Scripting type of the network." },
          name: { type: "string", description: "Old name of the network." },
          branch: { type: "boolean", description: "Branch naming convention." },
          add: { type: "boolean", description: "Force add suffix." }
        },
        required: ["type", "name", "branch", "add"]
      },
      {
        name: "wsdb_new_model_object",
        desc: "Create a new model object in the root.",
        params: {
          type: { type: "string", description: "Scripting type (Asset Group, Model Group, Master Group)." },
          name: { type: "string", description: "Name for the new object." }
        },
        required: ["type", "name"]
      },
      {
        name: "wsdb_path",
        desc: "Get the pathname of the master database.",
        params: {},
        required: []
      },
      {
        name: "wsdb_root_model_objects",
        desc: "Get all objects in the root of the database.",
        params: {},
        required: []
      },
      {
        name: "wsdb_result_root",
        desc: "Get the root used for results files.",
        params: {},
        required: []
      },
      {
        name: "wsdb_use_merge_version_control",
        desc: "Check if merge version control is used (WS Pro only).",
        params: {},
        required: []
      }
    ]

    wsdb_tools.each do |tool|
      t = MCP::Tool.new(
        tool[:name],
        tool[:desc],
        {
          type: "object",
          properties: tool[:params],
          required: tool[:required]
        }
      )
      @server.add_tool(t) do |args|
        begin
          # All methods require @db to be open
          raise "No database is open. Please open a database first." if @db.nil?
          case tool[:name]
          when "wsdb_copy_into_root"
            object = args["object"]
            bCopySims = args["bCopySims"]
            bCopyGroundModels = args["bCopyGroundModels"]
            mo = @db.copy_into_root(object, bCopySims, bCopyGroundModels)
            { status: 'success', model_object: mo }
          when "wsdb_file_root"
            { status: 'success', file_root: @db.file_root }
          when "wsdb_find_model_object"
            mo = @db.find_model_object(args["type"], args["name"])
            { status: 'success', model_object: mo }
          when "wsdb_find_root_model_object"
            mo = @db.find_root_model_object(args["type"], args["name"])
            { status: 'success', model_object: mo }
          when "wsdb_guid"
            { status: 'success', guid: @db.guid }
          when "wsdb_list_read_write_run_fields"
            arr = []
            @db.list_read_write_run_fields { |fn| arr << fn }
            { status: 'success', fields: arr }
          when "wsdb_model_object"
            mo = @db.model_object(args["scripting_path"])
            { status: 'success', model_object: mo }
          when "wsdb_model_object_collection"
            moc = @db.model_object_collection(args["type"])
            { status: 'success', collection: moc }
          when "wsdb_model_object_from_type_and_guid"
            mo = @db.model_object_from_type_and_guid(args["type"], args["guid"])
            { status: 'success', model_object: mo }
          when "wsdb_model_object_from_type_and_id"
            mo = @db.model_object_from_type_and_id(args["type"], args["id"])
            { status: 'success', model_object: mo }
          when "wsdb_new_network_name"
            newname = @db.new_network_name(args["type"], args["name"], args["branch"], args["add"])
            { status: 'success', new_name: newname }
          when "wsdb_new_model_object"
            mo = @db.new_model_object(args["type"], args["name"])
            { status: 'success', model_object: mo }
          when "wsdb_path"
            { status: 'success', path: @db.path }
          when "wsdb_root_model_objects"
            moc = @db.root_model_objects
            { status: 'success', collection: moc }
          when "wsdb_result_root"
            { status: 'success', result_root: @db.result_root }
          when "wsdb_use_merge_version_control"
            b = @db.use_merge_version_control?
            { status: 'success', use_merge_version_control: b }
          else
            { status: 'error', message: 'Unknown WSDatabase tool' }
          end
        rescue => e
          { status: 'error', message: e.message }
        end
      end
    end

    # Tool: Get/Set Working and Results Folder
    folder_tool = MCP::Tool.new(
      "icm_folders",
      "Get or set the ICM working and results folders.",
      {
        type: "object",
        properties: {
          action: { type: "string", enum: ["get", "set"], description: "Whether to get or set the folders." },
          working_folder: { type: ["string", "null"], description: "Path to set as working folder (required for set)." },
          results_folder: { type: ["string", "null"], description: "Path to set as results folder (required for set)." }
        },
        required: ["action"]
      }
    )

    @server.add_tool(folder_tool) do |args|
      begin
        action = args["action"]
        if action == "get"
          {
            status: 'success',
            working_folder: WSApplication.working_folder,
            results_folder: WSApplication.results_folder
          }
        elsif action == "set"
          wf = args["working_folder"]
          rf = args["results_folder"]
          WSApplication.set_working_folder(wf) if wf && !wf.strip.empty?
          WSApplication.set_results_folder(rf) if rf && !rf.strip.empty?
          {
            status: 'success',
            working_folder: WSApplication.working_folder,
            results_folder: WSApplication.results_folder
          }
        else
          { status: 'error', message: 'Invalid action. Use "get" or "set".' }
        end
      rescue => e
        { status: 'error', message: e.message }
      end
    end

    # Tool: Create ICM Database (Exchange only)
    create_db_tool = MCP::Tool.new(
      "create_icm_database",
      "Creates a new ICM database at the specified path. Optionally specify version.",
      {
        type: "object",
        properties: {
          path: { type: "string", description: "Path or server string for the new database." },
          version: { type: ["string", "null"], description: "Optional database version (e.g. '2023.0', '2023.1', 'WS Pro 2023.0')." }
        },
        required: ["path"]
      }
    )

    @server.add_tool(create_db_tool) do |args|
      begin
        path = args["path"]
        version = args["version"]
        if version.nil? || version.to_s.strip.empty?
          db = WSApplication.create(path)
        else
          db = WSApplication.create(path, version)
        end
        { status: 'success', message: "Database created", path: path, version: version }
      rescue => e
        { status: 'error', message: e.message }
      end
    end

    # Tool: Create Transportable ICM Database (Exchange only)
    create_transportable_tool = MCP::Tool.new(
      "create_icm_transportable",
      "Creates a new transportable ICM database at the specified path. Optionally specify version.",
      {
        type: "object",
        properties: {
          path: { type: "string", description: "Path for the new transportable database." },
          version: { type: ["string", "null"], description: "Optional database version (e.g. '2023.0', '2023.1', 'WS Pro 2023.0')." }
        },
        required: ["path"]
      }
    )

    @server.add_tool(create_transportable_tool) do |args|
      begin
        path = args["path"]
        version = args["version"]
        if version.nil? || version.to_s.strip.empty?
          db = WSApplication.create_transportable(path)
        else
          db = WSApplication.create_transportable(path, version)
        end
        { status: 'success', message: "Transportable database created", path: path, version: version }
      rescue => e
        { status: 'error', message: e.message }
      end
    end
    # Registering tools for InfoWorks ICM MCP Server
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

    @server.add_tool(open_db_tool) do |args|
      begin
        dbname = args["dbname"]
        if dbname.nil? || dbname.to_s.strip.empty?
          @db = WSApplication.open
        else
          @db = WSApplication.open(dbname)
        end
        { status: 'success', message: "Database Opened", dbname: dbname }
      rescue => e
        { status: 'error', message: e.message }
      end
    end

    open_network_tool = MCP::Tool.new(
      "open_icm_network",
      "Opens a network in the currently open InfoWorks ICM database using model_object_from_type_and_id. Requires network id (integer). Returns error if fails or if database is not open.",
      {
        type: "object",
        properties: {
          id: { type: "integer", description: "Network ID (integer)" },
          dbname: { type: "string", description: "Database name from which to open network (string)" }
        },
        required: ["id"]
      }
    )

    @server.add_tool(open_network_tool) do |args|
      begin
        if @db.nil? && args["dbname"].nil?
          raise "No database is open. Please open a database first."
        end

        unless args["dbname"].nil?
          @db = WSApplication.Open(args["dbname"])
          raise "Database with name '#{args["dbname"]}' not found." if @db.nil?
        end

        id = args["id"]
        @net = @db.model_object_from_type_and_id("Model Network", id)
        if @net.nil?
          { status: 'error', message: "Network with id #{id} not found." }
        else
          { status: 'success', message: "Network opened", id: id, name: @net.name }
        end
      rescue => e
        { status: 'error', message: e.message }
      end
    end

    # Tool: Run Ruby script in ICM environment using a thread
    run_icm_script_tool = MCP::Tool.new(
      "run_ruby_script",
      "Runs a Ruby script in the ICM environment.",
      {
        type: "object",
        properties: {
          string_script: { type: "string", description: "Absolute path to the Ruby script to run." },
          icm_exe: { type: "string", description: "Path to ICM IExchange.exe executable (optional, will use default if not provided)." },
          args: { type: "array", items: { type: "string" }, description: "Additional arguments for the script (optional)." },
        },
        required: ["script_path"]
      }
    )

    # add to tool
    server.add_tool(run_icm_script_tool) do |args|
      script_path = args["script_path"]
      icm_exe = args["icm_exe"]
      extra_args = args["args"] || []

      unless File.exist?(script_path)
        raise "Script file not found: #{script_path}"
      end

      unless File.exist?(exe)
        raise "ICM executable not found: #{exe}"
      end

      # Build command
      cmd = [exe, script_path, "/ICM"] + extra_args
      cmd_str = cmd.map { |c| c.include?(" ") ? '"' + c + '"' : c }.join(' ')

      # Run in a background thread
      Thread.new do
        begin
          system(cmd_str)
        rescue => e
          puts "Error running script: #{e.message}"
      end
    end
  end
  
  def run
    transport = MCP::StdioTransport.new
    @server.set_transport(transport)
    puts "MCP Ruby Server v#{MCP::VERSION} ready on stdio"
    puts "Protocol version: #{MCP::PROTOCOL_VERSION}"
    @server.run
  end
end

# To run the server:
# server = ICMMCPServer.new
# server.run