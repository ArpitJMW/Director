class AddPipelineModeToProjects < ActiveRecord::Migration[8.1]
  def change
    # "auto" = each stage chains to the next, pausing only at review checkpoints;
    # "manual" = the legacy per-stage-button behaviour.
    add_column :projects, :pipeline_mode, :string, null: false, default: "manual"
    # nil = running / not started; "storyboard" and "review" are the two pauses.
    add_column :projects, :pipeline_checkpoint, :string
  end
end
