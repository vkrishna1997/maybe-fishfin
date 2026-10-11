class DefaultCollapseAccountSidebar < ActiveRecord::Migration[7.2]
  def up
    change_column_default :users, :show_sidebar, from: true, to: false
    execute "UPDATE users SET show_sidebar = false"
  end

  def down
    change_column_default :users, :show_sidebar, from: false, to: true
    execute "UPDATE users SET show_sidebar = true"
  end
end
