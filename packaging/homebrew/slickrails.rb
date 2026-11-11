# Homebrew formula for slickrails.
# Publish flow (after the first GitHub release):
#   1. Create a tap repo: github.com/<owner>/homebrew-slickrails
#   2. Fill in `url` with the release tarball and `sha256` with its checksum
#      (curl -L <url> | shasum -a 256)
#   3. Copy this file into the tap as Formula/slickrails.rb
#   4. Users install with: brew install <owner>/slickrails/slickrails
class Slickrails < Formula
  desc "Guardrails for AI-built codebases — hooks, CI, AI review, feature dossiers"
  homepage "https://github.com/l0kl97/slickrails"
  url "https://github.com/l0kl97/slickrails/archive/refs/tags/v1.5.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_TARBALL_SHA256"
  license "MIT"

  depends_on "git"

  def install
    libexec.install Dir["*"], Dir[".*"].reject { |f| f =~ /\A\.\.?\z/ }
    (bin/"slickrails").write_env_script libexec/"bin/slickrails", {}
  end

  test do
    assert_match(/\d+\.\d+\.\d+/, shell_output("#{bin}/slickrails version"))
  end
end
