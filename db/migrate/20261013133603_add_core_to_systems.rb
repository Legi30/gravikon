class AddCoreToSystems < ActiveRecord::Migration[8.0]
  # Core systems are the four demo systems the app is built around: they
  # cannot be deleted, regenerated or edited (demo:reset recreates them with
  # core: true every night; the backfill covers the time until then)
  def up
    add_column :systems, :core, :boolean, default: false, null: false
    execute "UPDATE systems SET core = 1 WHERE name IN ('Alfa Centauri', 'Kepler-442', 'Trappist', 'Proxima')"
  end

  def down
    remove_column :systems, :core
  end
end
