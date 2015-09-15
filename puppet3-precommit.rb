#!/usr/bin/env ruby
require 'YAML'
require 'open3'

$yaml_changes = []
$puppet_changes = []
$commit_errors = false
$commit_errors_verbose = []

def check_hiera
  errors = 0
  yaml_error_list = []
  $yaml_changes.each do |y|
    begin
      YAML.load_file(y.to_s)
    rescue Exception => yerr
      yaml_error_list.push("malformed yaml in #{y}")
      yaml_error_list.push(yerr.message)
      errors += 1
    end
  end
  if errors > 0
    $commit_errors = true
    $commit_errors_verbose.push('YAML to be committed contains errors:')
    $commit_errors_verbose.push(yaml_error_list.to_s)
  end

end

def lint_puppet_file
  errors = 0
  lint_error_list = []
  $puppet_changes.each do |pl|
    plerr = ''
    pl_check = "puppet-lint #{pl.to_s} 1>&2"
    Open3.popen3(pl_check) do |i,o,e,w|
      plerr = e.read.chomp.to_s
    end
    if plerr.length > 0
      lint_error_list.push("lint error in #{pl}")
      lint_error_list.push(plerr.to_s)
      errors += 1
    end
    if errors > 0
      $commit_errors = true
      $commit_errors_verbose.push('pp files to be committed contain lint errors:')
      $commit_errors_verbose.push(lint_error_list)
    end
  end
end

def check_puppetfile
  errors = 0
  puppet_error_list = []
  $puppet_changes.each do |pc|
    begin
      pcerr = ''
      pc_check = "puppet parser validate #{pc.to_s}"
      Open3.popen3(pc_check) do |stdin, stdout, stderr, wait_thr|
        pcerr = stderr.read.chomp.to_s
      end
      if pcerr.length > 0
          puppet_error_list.push("puppet parser error(s) in #{pc}")
          puppet_error_list.push(pcerr.to_s)
          errors += 1
      end
      if errors > 0
        $commit_errors = true
        $commit_errors_verbose.push('pp files to be committed contain parser errors:')
        $commit_errors_verbose.push(puppet_error_list)
      end
    end
  end
  unless errors > 0
    lint_puppet_file
  end
end

#Main Bit

# Find top level of the repo to work from
repo_root = `git rev-parse --show-toplevel`.strip
abort "No .git directory found." unless File.directory?(repo_root)
Dir.chdir repo_root

# Get list of staged files
staged = `git diff --cached --name-only --diff-filter=ACM`.split(/\n/)

staged.each do |st|
  case File.extname(st)
  when '.yaml' || '.yml'
      $yaml_changes.push(st.to_s)
    when '.pp'
      $puppet_changes.push(st.to_s)
  end
end

if $yaml_changes.length > 0
  check_hiera
end

if $puppet_changes.length > 0
  check_puppetfile
end

if $commit_errors
  $commit_errors_verbose.each do |err|
    puts err
  end
  exit 1
end
