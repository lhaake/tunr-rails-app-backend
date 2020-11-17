# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)


Song.create([
  { title: 'Dreams', artist: 'Fleetwood Mac', time: '4:17', favorite: false },
  { title: 'Everywhere', artist: 'Fleetwood Mac', time: '3:46', favorite: false },
  { title: 'Gypsy', artist: 'Fleetwood Mac', time: '4:24', favorite: false },
  { title: 'Landslide', artist: 'Fleetwood Mac', time: '3:19', favorite: false },
  { title: 'Seven Wonders', artist: 'Fleetwood Mac', time: '3:42', favorite: false }
]);

puts "seed successful"