class ScenePolicy < ApplicationPolicy
  def show? = owner?
  def update? = owner?
  def generate? = owner?

  private

  def owner?
    record.project.user_id == user.id
  end

  class Scope < Scope
    def resolve
      scope.joins(:project).where(projects: { user_id: user.id })
    end
  end
end
