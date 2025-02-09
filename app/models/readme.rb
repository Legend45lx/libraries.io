# frozen_string_literal: true

# == Schema Information
#
# Table name: readmes
#
#  id            :integer          not null, primary key
#  html_body     :text
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  repository_id :integer
#
# Indexes
#
#  index_readmes_on_repository_id  (repository_id) UNIQUE
#
class Readme < ApplicationRecord
  VALID_EXTENSION_REGEXES = [
    /md/,
    /mdown/,
    /mkdn/,
    /mdn/,
    /mdtext/,
    /markdown/,
    /textile/,
    /org/,
    /creole/,
    /adoc|asc(iidoc)?/,
    /re?st(\.txt)?/,
    /pod/,
    /rdoc/,
  ].freeze

  belongs_to :repository
  validates_presence_of :html_body, :repository
  after_validation :reformat
  after_commit :check_unmaintained

  def self.format_markup(path, content)
    return unless content.present?
    return unless supported_format?(path)

    GitHub::Markup.render(path, content.force_encoding(Encoding::UTF_8))
  rescue GitHub::Markup::CommandError
    nil
  end

  def self.supported_format?(path)
    VALID_EXTENSION_REGEXES.any? do |regexp|
      path =~ /\.(#{regexp})\z/
    end
  end

  def to_s
    @to_s ||= Nokogiri::HTML(html_body).css("body").try(:inner_html)
  end

  def plain_text
    @plain_text ||= Nokogiri::HTML(html_body).try(:text)
  end

  def check_unmaintained
    return unless unmaintained?

    repository.update_attribute(:status, "Unmaintained")
    repository.projects.each do |project|
      project.update_attribute(:status, "Unmaintained")
    end
  end

  def unmaintained?
    html_body.downcase.gsub("\n", "").include?("unmaintained.tech/badge.svg")
  end

  def reformat
    doc = Nokogiri::HTML(html_body)
    doc.xpath("//a").each do |d|
      rel_url = d.get_attribute("href")
      begin
        d.set_attribute("href", URI.join(repository.blob_url, rel_url)) if rel_url.present? && !rel_url.match(/^#/) && URI.parse(rel_url)
      rescue NoMethodError, URI::InvalidURIError, URI::InvalidComponentError # rubocop: disable Lint/SuppressedException
      end
    end
    doc.xpath("//img").each do |d|
      rel_url = d.get_attribute("src")

      begin
        d.set_attribute("src", URI.join(repository.raw_url, rel_url)) if rel_url.present? && URI.parse(rel_url)
      rescue NoMethodError, URI::InvalidURIError, URI::InvalidComponentError # rubocop: disable Lint/SuppressedException
      end
    end
    self.html_body = doc.to_html(encoding: Encoding::UTF_8)
  end
end
