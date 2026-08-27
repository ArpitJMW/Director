class ProjectPolicy < ApplicationPolicy
  def show? = owner?
  def create? = user.present?
  def update? = owner?
  def destroy? = owner?

  # Pipeline actions (script/storyboard/render/regenerate) — same as edit.
  def generate? = owner?

  private

  def owner?
    record.user_id == user.id
  end

  class Scope < Scope
    def resolve
      scope.where(user_id: user.id)
    end
  end
end
