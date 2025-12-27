const bcrypt = require('bcryptjs');

exports.seed = async function(knex) {
  // Delete existing entries (optional - remove if you want to keep existing users)
  await knex('users').del();

  // Hash the passwords
  const hashedPassword = await bcrypt.hash('12345678', 10);

  // Insert seed entries
  await knex('users').insert([
    {
      first_name: 'Ruben',
      last_name: 'Dreyer',
      username: 'rubendreyer',
      password: hashedPassword,
      verified: true,
      created_at: new Date(),
      updated_at: new Date()
    },
    {
      first_name: 'Daniela',
      last_name: 'Dreyer',
      username: 'daniela',
      password: hashedPassword,
      verified: true,
      created_at: new Date(),
      updated_at: new Date()
    }
  ]);

  console.log('✓ Seed users created successfully!');
};
