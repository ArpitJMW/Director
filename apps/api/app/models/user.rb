class User < ApplicationRecord
  include HasPublicId
  has_public_id :user

  # Devise modules. JWT auth is issued/revoked via the :jwt_authenticatable
  # strategy backed by the JwtDenylist revocation store.
  devise :database_authenticatable, :registerable,
         :recoverable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: JwtDenylist

  has_many :projects, dependent: :destroy
  has_many :templates, foreign_key: :owner_id, dependent: :nullify, inverse_of: :owner

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true, length: { maximum: 120 }
end
