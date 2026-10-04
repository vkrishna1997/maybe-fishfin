class CreateGoals < ActiveRecord::Migration[7.2]
  def change
    create_table :goals, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.decimal :target_amount, precision: 19, scale: 4, null: false
      t.decimal :current_amount, precision: 19, scale: 4, default: "0.0", null: false
      t.date :target_date
      t.string :currency, null: false
      t.string :color, default: "#4da568", null: false

      t.timestamps
    end
  end
end
