# frozen_string_literal: true

require "rails_helper"

describe PackageManager::Base::BulkVersionUpdater do
  describe "#run!" do
    let(:db_project) { Project.create(platform: "Pypi", name: project_name) }
    let(:api_version_1) { PackageManager::Base::ApiVersion.new(version_number: "1.0.0", published_at: 2.days.ago) }
    let(:api_version_2) { PackageManager::Base::ApiVersion.new(version_number: "2.0.0", published_at: 1.days.ago) }
    let(:api_version_3) { PackageManager::Base::ApiVersion.new(version_number: "3.0.0", published_at: 1.hour.ago) }

    let(:bulk_version_updater) { described_class.new(db_project: db_project, versions_to_upsert_attrs: versions_to_upsert_attrs) }

    context "with a single version" do
      let(:versions_to_upsert_attrs) { [api_version_1] }

      it "updates a single version" do
        bulk_version_updater.run!
        # TODO
      end

      it "updates a single version twice without recreating it" do
        bulk_version_updater.run!
        bulk_version_updater.run!
        # TODO
      end
    end

    context "with three versions" do
      let(:versions_to_upsert_attrs) { [api_version_1, api_version_2] }

      it "inserts three versions" do
        bulk_version_updater.run!
        # TODO
      end

      it "updates three versions" do
        bulk_version_updater.run!
        bulk_version_updater.run!
        # TODO
      end
    end

    # TODO: spec for new repository_source
    # TODO: spec for adding a repository_source
    # TODO: spec for adding no repository_source to existing repository_source
    # TODO: spec for invalid record raising error
    # TODO: spec for before_save callbacks
    # TODO: spec for after_create_commit callbacks
  end
end
