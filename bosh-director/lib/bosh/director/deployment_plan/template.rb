require 'bosh/template/property_helper'

module Bosh::Director
  module DeploymentPlan
    class Template
      include Bosh::Template::PropertyHelper

      attr_reader :name
      attr_reader :release

      attr_reader :model
      attr_reader :package_models

      attr_reader :link_infos
      attr_reader :deployment_manifest_template_properties

      # @param [DeploymentPlan::ReleaseVersion] release Release version
      # @param [String] name Template name
      def initialize(release, name)
        @release = release
        @name = name
        @model = nil
        @package_models = []
        @logger = Config.logger
        @link_infos = {}
        @deployment_manifest_template_properties = nil
      end

      # Looks up template model and its package models in DB
      # @return [void]
      def bind_models
        @model = @release.get_template_model_by_name(@name)

        if @model.nil?
          raise DeploymentUnknownTemplate, "Can't find template `#{@name}'"
        end

        @package_models = @model.package_names.map do |name|
          @release.get_package_model_by_name(name)
        end
      end

      def bind_existing_model(model)
        @model = model
      end

      # Downloads template blob to a given path
      # @return [String] Path to downloaded blob
      def download_blob
        uuid = SecureRandom.uuid
        path = File.join(Dir.tmpdir, "template-#{uuid}")

        @logger.debug("Downloading template `#{@name}' (#{blobstore_id})...")
        t1 = Time.now

        File.open(path, "w") do |f|
          App.instance.blobstores.blobstore.get(blobstore_id, f)
        end

        @logger.debug("Template `#{@name}' downloaded to #{path} " +
                      "(took #{Time.now - t1}s)")

        path
      end

      # @return [String]
      def version
        present_model.version
      end

      # @return [String]
      def sha1
        present_model.sha1
      end

      # @return [String]
      def blobstore_id
        present_model.blobstore_id
      end

      # @return [Array]
      def logs
        present_model.logs
      end

      # @return [Hash]
      def properties
        present_model.properties
      end

      # return [Array]
      def model_consumed_links
        present_model.consumes.to_a.map { |l| TemplateLink.parse("consumes", l) }
      end

      # return [Array]
      def model_provided_links
        present_model.provides.to_a.map { |l| TemplateLink.parse('provides', l) }
      end

      # return [Array]
      def consumed_links(job_name)
        if @link_infos[job_name] != nil && @link_infos[job_name]["consumes"]  != nil
          @link_infos[job_name]["consumes"].map { |_, link_info| TemplateLink.parse("consumes", link_info) }
        else
          return []
        end
      end

      # return [Array]
      def provided_links(job_name)
        if @link_infos[job_name] != nil && @link_infos[job_name]["provides"] != nil
          @link_infos[job_name]["provides"].map { |_, link_info| TemplateLink.parse("provides", link_info) }
        else
          return []
        end
      end

      def add_link_info(job_name, kind, link_name, source)
        @link_infos[job_name] ||= {}
        @link_infos[job_name][kind] ||= {}
        @link_infos[job_name][kind][link_name] ||= {}

        if source.eql? 'nil'
          # This is the case where the user set link source to nil explicitly in the deployment manifest
          # We should skip the binding of this link, even if it exist. This is used only when the link
          # is optional
          @link_infos[job_name][kind][link_name]['skip_link'] = true
        else
          source.to_a.each do |key, value|
            @link_infos[job_name][kind][link_name][key] = value
          end
        end

      end

      def consumes_link_info(job_name, link_name)
        @link_infos.fetch(job_name, {}).fetch('consumes', {}).fetch(link_name, {})
      end

      def add_deployment_manifest_template_properties(template_scoped_properties)
        @deployment_manifest_template_properties = template_scoped_properties
      end

      def has_local_properties
        return !@deployment_manifest_template_properties.nil?
      end

      def bind_local_properties
        bound_template_specific_properties = {}
        properties.each_pair do |name, definition|
          copy_property(
              bound_template_specific_properties,
              @deployment_manifest_template_properties,
              name,
              definition["default"]
          )
        end
        @deployment_manifest_template_properties = bound_template_specific_properties
      end

      private

      # Returns model only if it's present, fails otherwise
      # @return [Models::Template]
      def present_model
        if @model.nil?
          raise DirectorError, "Template `#{@name}' model is unbound"
        end
        @model
      end
    end
  end
end
