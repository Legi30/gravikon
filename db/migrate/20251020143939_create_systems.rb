# frozen_string_literal: true

class CreateSystems < ActiveRecord::Migration[8.0]
  def change
    create_table :systems do |t|
      t.string :name, null: false
      t.float :x, null: false
      t.float :y, null: false
      t.string :json_file_path, null: false

      t.timestamps
    end

    add_index :systems, :name, unique: true
  end
end
