class PreflightReportPolicy < ApplicationPolicy
  def show? = owner?
  def update? = owner? # acknowledge warnings

  private

  def owner?
    record.project.user_id == user.id
  end
end
