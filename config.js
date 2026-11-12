/* Per-company settings. This is the ONLY file that changes between companies.
   Copy the project, edit this file, deploy. See NEW_CLIENT_GUIDE.md. */
window.APP_CONFIG = {
  supabaseUrl: 'https://iyebirclmvrafcvvgpey.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml5ZWJpcmNsbXZyYWZjdnZncGV5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc1Mjg1NTEsImV4cCI6MjEwMzEwNDU1MX0.Lb7hwkonMMeeXs5em4rzZ9tLdTsAPdUZykXMlgEJiFs',   // the public "anon" key is meant to be in the browser; it is safe once the database is locked (new_client_setup.sql does that)
  loginDomain: 'innochem.app',          // hidden part of login emails: username@loginDomain (must match new_client_setup.sql)
  brand: 'Inno Chem Bangladesh',        // company name shown before the profile loads, and the fallback everywhere
  tagline: 'Your Textile Partner',
  product: 'RAR TECH',                  // "Powered by" name in the footer
  currency: '৳',                   // currency sign
  businessType: 'textile-chemicals trading business',   // told to the AI assistant
  country: 'Bangladesh',
  modules: {                            // set false to hide a part of the app this company does not use
    recipes: true, production: true, salesOrders: true, deliveries: true,
    analyst: true, expenses: true, datahealth: true, receivables: true, approvals: true
  }
};
