
# Versioned prompt templates (planning-doc §25). Each stage keeps its system
# prompt in app/prompts/<stage>/vN.txt so prompts are diffable, reviewable, and
# pinned per generation (the version is recorded on ai_generations.request).
#
#   tpl = Prompts.load("scene_planner")   # highest version
#   tpl.text        #=> the system prompt string
#   tpl.version     #=> 1
module Prompts
  Template = Data.define(:name, :version, :text)

  ROOT = Rails.root.join("app/prompts")

  module_function

  # @param name [String] stage folder under app/prompts
  # @param version [Integer, nil] pin a version; nil picks the highest
  def load(name, version: nil)
    dir = ROOT.join(name)
    files = Dir[dir.join("v*.txt")]
    raise ArgumentError, "no prompt templates in #{dir}" if files.empty?

    versions = files.to_h { |f| [ File.basename(f)[/\Av(\d+)\.txt\z/, 1].to_i, f ] }
    v = version || versions.keys.max
    path = versions[v] or raise ArgumentError, "no #{name} prompt v#{version}"

    Template.new(name: name, version: v, text: File.read(path).strip)
  end
end
