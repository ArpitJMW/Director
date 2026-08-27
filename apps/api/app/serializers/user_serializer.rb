# Plain serializer — no gem. Returns the public representation of a user.
class UserSerializer
  def self.call(user)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      created_at: user.created_at.iso8601
    }
  end
end
