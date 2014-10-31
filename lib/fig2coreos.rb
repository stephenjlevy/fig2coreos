require 'yaml'
require 'fileutils'

class Fig2CoreOS
  def self.convert(cust_name, app_name, fig_file, output_dir, options={})
    Fig2CoreOS.new(cust_name, app_name, fig_file, output_dir, options)
  end

  def initialize(cust_name, app_name, fig_file, output_dir, options={})
    @cust_name = cust_name
    @app_name = app_name
    @fig = YAML.load_file(fig_file.to_s)
    @output_dir = File.expand_path(output_dir.to_s)

    # clean and setup directory structure
    FileUtils.rm_rf(Dir[File.join(@output_dir, "*.service")])

    create_service_files
    exit 0
  end

  def create_service_files
  	@fig.each do |service_name, service|
      image = service["image"]
      command = service["command"]
      args = service["args"]
      ports = []
      first_port = (service["ports"] || [])[0]
      first_port_lowercase = String.new
      if (first_port.is_a? String)
        first_port_lowercase = first_port.downcase
      end
      if (first_port_lowercase == "all")
        ports = ["-P"]
      else
        ports = (service["ports"] || []).map{|port| "-p #{port}"}
      end
      volumes = (service["volumes"] || []).map{|volume| "-v #{volume}"}
      links = (service["links"] || []).map do |name, name_alias|
        "--link #{@cust_name}.#{name}:#{name_alias}"
      end

      envs = (service["environment"] || []).map do |env_name, env_value|
        "-e \"#{env_name}=#{env_value}\""
      end

      discovery = "ExecStartPost=/bin/sh -c \""
      stop_discovery = String.new
      discovery_enabled = false
      (service["discovery"] || []).map do |service, port|
        discovery_enabled = true
        discovery += "until docker inspect --format='{{(index (index .NetworkSettings.Ports \\\"#{port}/tcp\\\") 0).HostPort}}' #{@cust_name}.#{service_name} >/dev/null 2>&1; do sleep 2;done; /usr/bin/etcdctl set /#{@cust_name}/#{@app_name}/#{service} %H:$(docker inspect --format='{{(index (index .NetworkSettings.Ports \\\"#{port}/tcp\\\") 0).HostPort}}' #{@cust_name}.#{service_name}); "
      end

      if discovery_enabled
        discovery += "\""
      else
        discovery = String.new
      end

      if !discovery.empty?
        stop_discovery = "ExecStop=-/usr/bin/etcd rm /cust1/#{service_name}"
      end

      links = (service["links"] || []).map do |name, name_alias|
        "--link #{@cust_name}.#{name}:#{name_alias}"
      end


      after = String.new
      requires = String.new
      if service["links"]
        (service["links"]).each do |name, name_alias|
          after += "After=#{@cust_name}.#{name}.1.service\n"
          requires += "Requires=#{@cust_name}.#{name}.1.service\n"
        end
      else
        after = "After=docker.service"
        requires = "Requires=docker.service"
      end

      #FIXME: Handle wildcards
      conflicts = (service["conflicts"] || []).map{|conflict| "Conflicts=#{conflict}.1.service"}

      machines_of = (service["machine_of"] || []).map{|machine_of| "MachineOf=#{@cust_name}.#{machine_of}.1.service"}

      machine_ids = (service["machine_id"] || []).map{|machine_id| "MachineId=#{machine_id}"}

      machine_metadata_info = (service["machine_metadata"] || []).map{|machine_metadata| "MachineMetadata=#{machine_metadata}"}

      binds_to_units = (service["binds_to"] || []).map{|binds_to| "BindsTo=#{@cust_name}.#{binds_to}.1.service"}

      global = service["global"]
      if global == true
        global = "Global=true"
      end


      base_path = @output_dir


  		File.open(File.join(base_path, "#{@cust_name}.#{service_name}.1.service") , "w") do |file|
        file << <<-eof
[Unit]
Description=#{service_name}
#{after}
#{requires}
#{binds_to_units.join("\n")}


[Service]
Restart=always
RestartSec=10s
ExecStartPre=-/usr/bin/docker kill #{@cust_name}.#{service_name}
ExecStartPre=-/usr/bin/docker rm #{@cust_name}.#{service_name}
ExecStartPre=-/usr/bin/docker pull #{image}
ExecStart=/usr/bin/docker run --name #{@cust_name}.#{service_name} #{volumes.join(" ")} #{links.join(" ")} #{envs.join(" ")} #{ports.join(" ")} #{image} #{command} #{args}
#{discovery}
#{stop_discovery}
ExecStop=-/usr/bin/docker stop #{@cust_name}.#{service_name}

[X-Fleet]
#{conflicts.join("\n")}
#{machines_of.join("\n")}
#{machine_ids.join("\n")}
#{machine_metadata_info.join("\n")}
#{global}
eof
  		end


    end
  end
end
