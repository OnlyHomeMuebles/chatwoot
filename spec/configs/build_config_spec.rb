## Guards the production build recipe (Dokploy runs the railpack builder).
## Two failures already hit this deploy path and both are silent — they only show up as an OOM
## kill on the app container, never as a build error:
##   1. `"..."` in the build step expands to railpack's auto-generated Rails commands, which
##      already include `bundle exec rake assets:precompile`. Leaving it in front of the explicit
##      command runs the whole vite build twice, the first time with no heap cap and no skip flags.
##   2. Without SKIP_PNPM_INSTALL_DURING_PRECOMPILE, lib/tasks/build.rake reinstalls the full
##      node_modules tree that the install step already produced.
require 'rails_helper'

RSpec.context 'with the production build configuration' do
  let(:expected_node_heap_mb) { 4096 }

  let(:railpack) { JSON.parse(Rails.root.join('railpack.json').read) }
  let(:build_commands) { railpack.dig('steps', 'build', 'commands') }
  let(:precompile_command) { build_commands.first }

  it 'precompiles assets exactly once' do
    expect(build_commands).not_to include('...')
    expect(build_commands.grep(/assets:precompile/).size).to eq(1)
  end

  it 'keeps the bootsnap precompile that the expanded defaults used to provide' do
    expect(build_commands).to include(a_string_matching(/bootsnap precompile/))
  end

  it 'declares the start command that runs both the web process and Sidekiq' do
    expect(railpack.dig('deploy', 'startCommand')).to eq('bash deployment/start.sh')
  end

  it 'skips the browserslist update during precompile' do
    expect(precompile_command).to include('SKIP_BROWSERSLIST_UPDATE=true')
  end

  it 'caps the node heap at the measured requirement' do
    expect(node_heap_mb(precompile_command)).to eq(expected_node_heap_mb)
  end

  def node_heap_mb(text)
    text[/max-old-space-size=(\d+)/, 1].to_i
  end
end
