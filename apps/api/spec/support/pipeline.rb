# Helpers to fast-forward a project through the early pipeline stages in specs.
module PipelineHelpers
  def project_with_script(**attrs)
    project = attrs[:project] || create(:project, **attrs.except(:project))
    Ai::ScriptService.new(project: project).call
    project.reload
  end

  def project_with_storyboard(**attrs)
    project = project_with_script(**attrs)
    Ai::ScenePlannerService.new(project: project).call
    project.reload
  end
end

RSpec.configure { |c| c.include PipelineHelpers }
