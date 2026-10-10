/// <reference path="../pb_data/types.d.ts" />
// PocketBase starts every app with an open `users` collection: anyone may sign up. The
// owner signs in as the superuser instead (pb-auth.js), so close it. Delete this file
// before the first deploy if the app is meant to have public accounts.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");
  users.createRule = null;
  app.save(users);
}, (app) => {
  const users = app.findCollectionByNameOrId("users");
  users.createRule = "";
  app.save(users);
});
