# Rewrites the BLOG-POST-LIST block of the README with the latest posts from
# the blog feed.
#
# Usage: ruby update_readme.rb <readme_path> <feed_url>

require "net/http"
require "rexml/document"
require "time"

LATEST_COUNT = 10
DESCRIPTION_LENGTH = 180

readme_path, feed_url = ARGV
abort "Usage: ruby update_readme.rb <readme_path> <feed_url>" unless readme_path && feed_url

def fetch(url)
  response = Net::HTTP.get_response(URI(url))
  abort "Could not fetch #{url}: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  response.body.force_encoding(Encoding::UTF_8)
end

# REXML has already decoded the entities, so a post about ERB would otherwise
# put live HTML tags and Markdown into the README.
def escape(text)
  text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub(/([\\`*_\[\]])/) { "\\#{$1}" }
end

# jekyll-feed ends a cut summary with "[…]". Trim to whole words either way.
def excerpt(text)
  text = text.gsub(/\s+/, " ").strip
  cut = text.sub!(/\s*\[…\]\z/, "")
  if text.length > DESCRIPTION_LENGTH
    text = text[0, DESCRIPTION_LENGTH + 1].sub(/\s+\S*\z/, "")
    cut = true
  end
  cut ? "#{text}…" : text
end

def replace_block(readme, name, content)
  start_tag = "<!-- #{name}:START -->"
  end_tag = "<!-- #{name}:END -->"
  abort "README has no #{start_tag} / #{end_tag} block" unless readme.include?(start_tag) && readme.include?(end_tag)

  readme.sub(/#{Regexp.escape(start_tag)}.*?#{Regexp.escape(end_tag)}/m) { "#{start_tag}\n#{content}\n#{end_tag}" }
end

feed = REXML::Document.new(fetch(feed_url))
posts = REXML::XPath.match(feed, "//entry").map do |entry|
  # Atom makes rel optional (it defaults to alternate) and published optional.
  link = entry.elements["link[@rel='alternate']"] || entry.elements["link[not(@rel)]"]
  date = entry.elements["published"] || entry.elements["updated"]
  title = entry.elements["title"]&.text.to_s.strip
  next if link.nil? || date.nil? || title.empty?

  {
    title: title,
    url: link.attributes["href"],
    date: Time.parse(date.text),
    description: excerpt(entry.elements["summary"]&.text.to_s)
  }
end.compact
abort "No posts in #{feed_url}" if posts.empty?

latest = posts.sort_by { |post| post[:date] }.reverse.first(LATEST_COUNT).map do |post|
  "#### [#{escape(post[:title])}](<#{post[:url]}>)\n<sub>#{post[:date].strftime("%b %-d, %Y")}</sub>\n\n#{escape(post[:description])}\n"
end.join("\n")

File.write(readme_path, replace_block(File.read(readme_path), "BLOG-POST-LIST", latest))
