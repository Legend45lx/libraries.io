# frozen_string_literal: true

class PackageManager::Maven::Google < PackageManager::Maven::Common
  REPOSITORY_SOURCE_NAME = "Google"
  SUPPORTS_SINGLE_VERSION_UPDATE = true
  HIDDEN = true

  def self.repository_base
    "https://dl.google.com/dl/android/maven2"
  end

  def self.project_names
    []
  end

  def self.recent_names
    get("https://maven.libraries.io/googleMaven/recent")
  end

  # TODO: check and store if the value on the other end is a JAR or AAR file
  # This returns a link to the Google Maven docs where the JAR or AAR
  # file can be downloaded.
  def self.download_url(db_project, version = nil)
    if version
      "https://maven.google.com/web/index.html##{db_project.name}:#{version}"
    else
      "https://maven.google.com/web/index.html##{db_project.name}"
    end
  end

  # rubocop: disable Lint/UnusedMethodArgument
  def self.update(name, sync_version:, force_sync_dependencies: false)
    raw_project = project(
      name,
      latest: latest_version(name)
    )

    mapped_project = transform_mapping_values(mapping(raw_project))
    return false unless mapped_project.present?

    db_project = ensure_project(mapped_project, reformat_repository_url: true)

    api_versions = [
      version_hash_to_version_object(one_version_for_name(sync_version, name)),
    ]

    BulkVersionUpdater.new(
      db_project: db_project,
      api_versions: api_versions,
      repository_source_name: self::HAS_MULTIPLE_REPO_SOURCES ? [self::REPOSITORY_SOURCE_NAME] : nil
    ).run!

    finalize_db_project(db_project)
  end
  # rubocop: enable Lint/UnusedMethodArgument

  def self.latest_version(name)
    group_name, artifact = name.split(NAME_DELIMITER)

    group_path = group_name.gsub(".", "/")

    packages = Nokogiri::XML(get_raw("https://maven.google.com/#{group_path}/group-index.xml")).root.children.find_all(&:element?)

    packages.each do |package|
      package_name = package.name

      next unless package_name == artifact

      versions = package["versions"].split(",")

      return versions.last
    end

    nil
  end

  # This is called by the Rake task maven:populate_google_maven.
  # It lives here because re-creating all of the PackageManager-specific
  # code in the Rake task itself would be unreasonable to do.
  def self.update_all_versions
    main = Nokogiri::XML(get_raw("https://maven.google.com/master-index.xml"))

    main.css("metadata").children.find_all(&:element?).each do |group|
      group_name = group.name

      group_path = group_name.gsub(".", "/")

      packages = Nokogiri::XML(get_raw("https://maven.google.com/#{group_path}/group-index.xml")).root.children.find_all(&:element?)

      packages.each do |package|
        package_name = package.name

        version_numbers = package["versions"].split(",")

        name = [group_name, package_name].join(PackageManager::Maven::NAME_DELIMITER)

        raw_project = project(
          name,
          latest: version_numbers.last # not totally accurate but it's all we have at this point
        )

        mapped_project = transform_mapping_values(mapping(raw_project))
        return false unless mapped_project.present?

        db_project = ensure_project(mapped_project, reformat_repository_url: true)

        api_versions = version_numbers
          .map { |version_number| one_version_for_name(version_number, name) }
          .map { |mapped_version| version_hash_to_version_object(mapped_version) }

        retried = false
        begin
          BulkVersionUpdater.new(
            db_project: db_project,
            api_versions: api_versions,
            repository_source_name: self::HAS_MULTIPLE_REPO_SOURCES ? [self::REPOSITORY_SOURCE_NAME] : nil
          ).run!
        rescue Faraday::ConnectionFailed
          unless retried
            retried = true
            retry
          end
          retry unless retried
          StructuredLog.capture(
            "GOOGLE_MAVEN_VERSION_UPSERT_FAILURE",
            {
              project_id: db_project.id,
              versions: api_versions.map(&:version_number),
            }
          )
        end

        pp "added versions #{api_versions.map(&:version_number).join(', ')}"

        finalize_db_project(db_project)
      rescue Faraday::ConnectionFailed
        retry
      end

      sleep 5
    rescue Faraday::ConnectionFailed
      retry
    end
  end
end
