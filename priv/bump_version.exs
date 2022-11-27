defmodule BumpVersion.VersionUtils do
  @doc """
  A utility to help with managing releases:
  - Bumps your version number in mix.exs
  - Git tags your new version
  - Adds to your CHANGELOG ()

  1. Create a file RELEASE.md and copy and paste this into it as a template (you will have to un-indent it after pasting - there should be no indents):

  ```
  RELEASE_TYPE: patch

  - Fixed x
  - Added y
  ```

  2. Modify the RELEASE.md contents to suit (add your changes and what release type you want).

  Release type options:
  - major: 0.0.1 -> 1.0.0 (when you make incompatible API changes)
  - minor: 0.0.1 -> 0.1.0 (when you add functionality in a backwards compatible manner)
  - patch: 0.0.1 -> 0.0.2 (when you make backwards compatible bug fixes)

  2. Run in the terminal:

        mix run priv/bump_version.exs
  """
  @version_line_regex ~r/(\n\s*@version\s+")([^\n]+)("\n)/
  @version_line_readme_regex ~r/(?<=\"~>\s)\d{1,}.\d{1,}.\d{1,}(?=\",)/

  def bump_major(%Version{} = version) do
    %{version | major: version.major + 1, minor: 0, patch: 0}
  end

  def bump_minor(%Version{} = version) do
    %{version | minor: version.minor + 1, patch: 0}
  end

  def bump_patch(%Version{} = version) do
    %{version | patch: version.patch + 1}
  end

  def version_to_string(%Version{} = version) do
    "#{version.major}.#{version.minor}.#{version.patch}"
  end

  def get_version() do
    config = File.read!("mix.exs")

    case Regex.run(@version_line_regex, config) do
      [_line, _pre, version, _post] ->
        Version.parse!(version)

      _ ->
        raise "Invalid project version in your mix.exs file"
    end
  end

  def set_version_mix(_old_version, version) do
    version_string = version_to_string(version)
    contents = File.read!("mix.exs")

    replaced =
      Regex.replace(@version_line_regex, contents, fn _, pre, _version, post ->
        "#{pre}#{version_string}#{post}"
      end)

    File.write!("mix.exs", replaced)
  end

  def set_version_readme(_old_version, version) do
    if File.exists?("README.md") do
      version_string = version_to_string(version)

      contents = File.read!("README.md")

      replaced =
        Regex.replace(@version_line_readme_regex, contents, fn _, pre, _version, post ->
          "#{pre}#{version_string}#{post}"
        end)

      File.write!("README.md", replaced)
    end
  end

  def update_version(%Version{} = version, "major"), do: bump_major(version)
  def update_version(%Version{} = version, "minor"), do: bump_minor(version)
  def update_version(%Version{} = version, "patch"), do: bump_patch(version)
  def update_version(%Version{} = _version, type), do: raise("Invalid version type: #{type}")
end

defmodule BumpVersion.Changelog do
  @moduledoc """
  Functions to append entries to the changelog.
  """

  alias BumpVersion.VersionUtils

  @release_filename "RELEASE.md"
  @release_type_regex ~r/^(RELEASE_TYPE:\s+)(\w+)(.*)/s

  @changelog_filename "CHANGELOG.md"
  @changelog_entry_header_level 2
  @changelog_entries_marker "# Changelog\n"

  def remove_release_file() do
    File.rm!(@release_filename)
  end

  def extract_release_type() do
    contents = File.read!(@release_filename)

    {type, text} =
      case Regex.run(@release_type_regex, contents) do
        [_line, _pre, type, text] ->
          {type, String.trim(text)}

        _ ->
          raise "Invalid project version in your mix.exs file"
      end

    {type, text}
  end

  def changelog_entry(%Version{} = version, %DateTime{} = date_time, text) do
    header_prefix = String.duplicate("#", @changelog_entry_header_level)
    version_string = VersionUtils.version_to_string(version)

    date_time_string =
      date_time
      |> DateTime.truncate(:second)
      |> NaiveDateTime.to_string()

    """

    #{header_prefix} #{version_string} - #{date_time_string}

    #{text}
    """
  end

  def add_changelog_entry(entry) do
    contents = File.read!(@changelog_filename)
    [first, last] = String.split(contents, @changelog_entries_marker)

    replaced =
      Enum.join([
        first,
        @changelog_entries_marker,
        entry,
        last
      ])

    File.write!(@changelog_filename, replaced)
  end
end

defmodule BumpVersion.Git do
  @doc """
  This module contains some git-specific functionality
  """
  alias BumpVersion.VersionUtils

  def add_commit_and_tag(version) do
    version_string = VersionUtils.version_to_string(version)
    Mix.Shell.IO.cmd("git add .", [])
    Mix.Shell.IO.cmd(~s'git commit -m "Bumped version number to #{version_string}"')
    Mix.Shell.IO.cmd(~s'git tag -a #{version_string} -m "Version #{version_string}"')
  end
end

defmodule BumpVersion.Tests do
  @moduledoc """
  Functions to handle various test and formatting checks.
  """

  @using_credo true

  def run_tests!() do
    error_code = Mix.Shell.IO.cmd("mix test", [])

    if error_code != 0 do
      raise "This version can't be released because tests are failing."
    end

    :ok
  end

  def run_formatter_check!() do
    error_code = Mix.Shell.IO.cmd("mix format --check-formatted", [])

    if error_code != 0 do
      raise "This version can't be released because formatter checks are failing."
    end

    :ok
  end

  def run_credo_check!() do
    if @using_credo do
      error_code = Mix.Shell.IO.cmd("mix credo", [])

      if error_code != 0 do
        raise "This version can't be released because credo checks are failing."
      end
    end

    :ok
  end
end

defmodule BumpVersion do
  @moduledoc """
  Bumps the version number of the project.
  """

  alias BumpVersion.VersionUtils
  alias BumpVersion.Changelog
  alias BumpVersion.Git
  alias BumpVersion.Tests

  @doc """
  Runs the version bump process.
  """
  def run() do
    # Run tests, formatter checks, and credo before
    # generating the release. If any test fails, stop.
    Tests.run_tests!()
    Tests.run_formatter_check!()
    Tests.run_credo_check!()

    # Get the current version from the mix.exs file.
    version = VersionUtils.get_version()

    # Extract the changelog entry and add it to the changelog.
    # Use the information in the RELEASE.md file to bump the version number.
    {release_type, text} = Changelog.extract_release_type()
    new_version = VersionUtils.update_version(version, release_type)
    entry = Changelog.changelog_entry(new_version, DateTime.utc_now(), text)
    Changelog.add_changelog_entry(entry)

    # Set a new version on the mix.exs file
    VersionUtils.set_version_mix(version, new_version)

    # Set a new version in the `README.md` file, if present
    VersionUtils.set_version_readme(version, new_version)

    # Remove the release file
    Changelog.remove_release_file()

    # Commit the changes and ad a new 'v*.*.*' tag
    Git.add_commit_and_tag(new_version)
  end
end

# Generate a new release
BumpVersion.run()
