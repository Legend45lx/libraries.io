# frozen_string_literal: true

module PackageManager
  class Base
    class BulkVersionUpdater
      def initialize(
        db_project:,
        api_versions:,
      )
        @db_project = db_project
        @api_versions = api_versions
      end

      def run!
        attrs = @api_versions
          .map { |api_version| db_project.versions.new(api_version.to_version_model_attributes) }
          .each do |v| 
            # this value will get merged w/existing in the upsert_all query
            v.repository_sources = [self::REPOSITORY_SOURCE_NAME] if self::HAS_MULTIPLE_REPO_SOURCES
            # from Version#before_save
            v.update_spdx_expression
            # upsert_all doesn't do validation, so ensure they're valid here.
            v.validate! 
          end
          .map { |v| v.attributes.without("id", "created_at", "updated_at") }

        existing_version_ids = db_project.versions.pluck(:id)

        Version.upsert_all(
          attrs, 
          # handles merging any existing repository_sources with new repository_source:
          #   Prev       New       Result
          #   ["Main"]  ["Maven"]  ["Main", "Maven"]
          #   [nil]     ["Maven"]  ["Maven"]
          #   ["Main"]  [nil]      ["Main"]
          #   [nil]     [nil]      nil
          on_duplicate: Arel.sql(%Q!
            repository_sources = (CASE 
            WHEN (versions.repository_sources IS NULL AND EXCLUDED.repository_sources IS NULL)
              THEN NULL
            WHEN (versions.repository_sources @> EXCLUDED.repository_sources)
              THEN versions.repository_sources 
            ELSE 
              (COALESCE(versions.repository_sources, '[]'::jsonb) || COALESCE(EXCLUDED.repository_sources, '[]'::jsonb))
            END)
          !), 
          unique_by: [:project_id, :number]
        )

        db_project.versions.where.not(id: existing_version_ids)
          .each do |newly_inserted_version| 
            # from Version#after_create_commit
            newly_inserted_version.send_notifications_async
            newly_inserted_version.log_version_creation
          end
          # these Version#after_create_commits are project-scoped, so only need to run them on the first version
          .first
          .tap(&:update_repository_async)
          .tap(&:update_project_tags_async) 

        db_project.update(versions_count: db_project.versions.count) # make up for counter_culture not running
      end
    end
  end
end
