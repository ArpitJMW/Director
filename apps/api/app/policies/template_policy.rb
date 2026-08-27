class TemplatePolicy < ApplicationPolicy
  def show?
    record.status == "published" || record.owner_id == user.id
  end

  class Scope < Scope
    # Built-in published templates plus any the user owns.
    def resolve
      scope.where(status: "published").or(scope.where(owner_id: user.id))
    end
  end
end
