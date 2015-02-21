class GithubUser < ActiveRecord::Base
  has_many :github_contributions

  def avatar_url(size = 60)
    "https://avatars.githubusercontent.com/u/#{github_id}?size=#{size}"
  end

  def github_url
    "https://github.com/#{login}"
  end

  def to_s
    login
  end

  def to_param
    login.downcase
  end

  def repositories
    GithubRepository.where('full_name ILIKE ?', "#{login}/%")
  end
end
