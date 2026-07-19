#!/usr/bin/env ruby

require 'fileutils'
require 'json'
require 'net/http'
require 'uri'
require 'yaml'

config = YAML.load_file('_config.yml')
existing_projects = File.exist?('_data/github_projects.yml') ? YAML.load_file('_data/github_projects.yml') : []
existing_by_name = Array(existing_projects).each_with_object({}) do |project, memo|
  memo[project['name']] = project if project.is_a?(Hash) && project['name']
end
project_config = config.fetch('github_projects', {}) || {}
organization = project_config['organization'] || config['github_username']
repos = Array(project_config['pinned_repositories'])

abort('No github_projects.organization configured') if organization.to_s.empty?

projects = repos.map do |repo|
  uri = URI("https://api.github.com/repos/#{organization}/#{repo}")
  request = Net::HTTP::Get.new(uri)
  request['Accept'] = 'application/vnd.github+json'
  request['Authorization'] = "Bearer #{ENV['GITHUB_TOKEN']}" if ENV['GITHUB_TOKEN'].to_s != ''

  response = begin
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
  rescue StandardError => error
    warn "Could not fetch #{organization}/#{repo}: #{error.message}"
    nil
  end

  if response.is_a?(Net::HTTPSuccess)
    data = JSON.parse(response.body)
    existing = existing_by_name[repo] || {}
    {
      'name' => data['name'],
      'description' => data['description'] || existing['description'] || "Pinned repository from #{organization}.",
      'language' => data['language'] || existing['language'] || 'Repository',
      'stars' => data['stargazers_count'],
      'html_url' => data['html_url'],
      'image' => existing['image'],
      'image_alt' => existing['image_alt']
    }
  else
    warn "Could not fetch #{organization}/#{repo}: #{response.code}" if response
    existing = existing_by_name[repo] || {}
    {
      'name' => repo,
      'description' => existing['description'] || "Pinned repository from #{organization}.",
      'language' => existing['language'] || 'Repository',
      'stars' => existing['stars'] || 0,
      'html_url' => "https://github.com/#{organization}/#{repo}",
      'image' => existing['image'],
      'image_alt' => existing['image_alt']
    }
  end
end.map { |project| project.reject { |_key, value| value.nil? || value == '' } }

FileUtils.mkdir_p('_data')
File.write('_data/github_projects.yml', projects.to_yaml)
