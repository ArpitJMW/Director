class AddPublicIdToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :public_id, :string
    User.reset_column_information

    alphabet = ("a".."z").to_a + ("2".."9").to_a
    User.where(public_id: nil).find_each do |user|
      user.update_columns(public_id: "user_#{Array.new(12) { alphabet.sample }.join}")
    end

    change_column_null :users, :public_id, false
    add_index :users, :public_id, unique: true
  end

  def down
    remove_column :users, :public_id
  end
end
