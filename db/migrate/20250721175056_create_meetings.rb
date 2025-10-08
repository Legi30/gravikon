class CreateMeetings < ActiveRecord::Migration[8.0]
  def change
    create_table :meetings do |t|
      t.string :start_time
      t.string :end_time
      t.string :topic
      t.text :participants
      t.float :local_avg_duration
      t.float :avg_delay

      t.timestamps
    end
  end
end
