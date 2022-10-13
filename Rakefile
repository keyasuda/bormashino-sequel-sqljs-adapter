# frozen_string_literal: true

load 'bormashino/tasks/bormashino.rake'

desc 'build ruby.wasm with packed app'
task :default do
  Rake::Task['bormashino:pack'].invoke('--mapdir /gem::./gem/')
end
