class CreateSongs < ActiveRecord::Migration[6.1]
  def change
    create_table :songs do |t|
      t.string :title
      t.string :artist
      t.string :time
      t.boolean :favorite

      t.timestamps
    end
  end
end
