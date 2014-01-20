require "digest"
require "fileutils"

module Jekyll
  module Tags
    class UmlBlock < Liquid::Block
      include Liquid::StandardFilters

      @@globals = {
        "debug" => false,
        "center" => true, # add support to center image
        "uml_cmd" => "java -jar plantuml.jar -charset utf-8 $umlfile -o $output_directory",
        "output_directory" => "/assets/uml",
        "src_dir" => "",
        "dst_dir" => ""
      }

      @@generated_files = [ ]
      def self.generated_files
        @@generated_files
      end

      def self.uml_output_directory
        @@globals["output_directory"]
      end

      def initialize(tag_name, text, tokens)
        super
        # We now can adquire the options for this liquid tag
        @p = {}
        text.gsub("  ", " ").split(" ").each do |part|
          if part.split("=").count != 2
            raise SyntaxError.new("Syntax Error in tag 'uml'")
          end
          var,val = part.split("=")
          @p[var] = val
        end
      end

      def self.read_config(name, site)
        cfg = site.config["liquid_plantuml"]
        return if cfg.nil?
        value = cfg[name]
        @@globals[name] = value if !value.nil?
      end

      def self.init_globals(site)
        # Get all the variables from the config and remember them for future use.
        if !defined?(@@first_time)
          @@first_time = true
          @@globals.keys.each do |k|
            read_config(k, site)
          end
          @@globals["src_dir"] = File.join(site.config["source"], @@globals["output_directory"])
          @@globals["dst_dir"] = File.join(site.config["destination"], @@globals["output_directory"])
          # Verify and prepare the output folder if it doesn't exist
          FileUtils.mkdir_p(@@globals["src_dir"]) unless File.exists?(@@globals["src_dir"])
        end
      end

      def execute_cmd(cmd)
        cmd = cmd.gsub("\$output_directory", "." + @@globals["output_directory"])
        cmd = cmd.gsub("\$umlfile", @p["uml_fn"])
        puts cmd if @@globals["debug"]
        system(cmd)
        return ($?.exitstatus == 0)
      end

      def render(context)
        uml_source = super
        # fix initial configurations
        site = context.registers[:site]
        Tags::UmlBlock::init_globals(site)
        # if this UML code is already compiled, skip its compilation
        file_base = "uml-" + Digest::MD5.hexdigest(uml_source)
        png_file = file_base + ".png"
        @p["png_fn"] = File.join(@@globals["src_dir"], png_file)
        ok = true
        if !File.exists?(@p["png_fn"])
          puts "Compiling with UML..." if @@globals["debug"]

          @p["uml_fn"] = file_base + ".txt"

          uml_text = "@startuml"
          uml_text << uml_source
          uml_text << "@enduml"
          
          # Put the LaTeX source code to file
          uml_file = File.new(@p["uml_fn"], "w")
          uml_file.puts(uml_text)
          uml_file.close
          # Compile the document to PNG
          ok = execute_cmd(@@globals["uml_cmd"])
          # Delete temporary files
          Dir.glob(file_base + ".*").each do |f|
            File.delete(f)
          end
        end

        if ok
          # Add the file to the list of static files for the final copy once generated
          st_file = Jekyll::StaticFile.new(site, site.source, @@globals["output_directory"], png_file)
          @@generated_files << st_file
          site.static_files << st_file
          # Build the <img> tag to be returned to the renderer
          png_path = File.join(@@globals["output_directory"], png_file)
          if @@globals["center"]
            return "<div style=\"width:100%; text-align:center\"><img src=\"" + png_path + "\" /></div>"
          else
            return "<img src=\"" + png_path + "\" />"
          end
        else
          # Generate a block of text in the post with the original source
          resp = "Failed to render the following block of LaTeX:<br/>\n"
          resp << "<pre><code>" + uml_source + "</code></pre>"
          return resp
        end
      end
    end
  end

  class Site
    # Alias for the parent Site::write method (ingenious static override)
    alias :super_uml_write :write

    def write
      super_uml_write   # call the super method
      Tags::UmlBlock::init_globals(self)
      dest_folder = File.join(dest, Tags::UmlBlock::uml_output_directory)
      FileUtils.mkdir_p(dest_folder) unless File.exists?(dest_folder)

      # clean all previously rendered files not rendered in the actual build
      src_files = []
      Tags::UmlBlock::generated_files.each do |f|
        src_files << f.path
      end
      pre_files = Dir.glob(File.join(source, Tags::UmlBlock::uml_output_directory, "uml-*.png"))
      to_remove = pre_files - src_files
      to_remove.each do |f|
        File.unlink f if File.exists?(f)
        _, fn = File.split(f)
        df = File.join(dest, Tags::UmlBlock::uml_output_directory, fn)
        File.unlink df if File.exists?(df)
      end
    end
  end
end

Liquid::Template.register_tag('plantuml', Jekyll::Tags::UmlBlock)
