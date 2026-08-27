class AddFailedFromStatusToProjects < ActiveRecord::Migration[8.1]
  def change
    # Remembers which stage a project was in when it failed, so the pipeline can
    # resume from that stage (spec §28 — every stage independently retryable).
    add_column :projects, :failed_from_status, :string
  end
end
