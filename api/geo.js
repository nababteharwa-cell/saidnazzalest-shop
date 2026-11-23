// Returns the visitor's country (from Vercel's IP lookup) so the shop can show USD prices outside Jordan.
// Nothing is stored; the IP address itself is never sent back.
module.exports = (req, res) => {
  res.setHeader('Cache-Control', 'private, no-store');
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify({ country: req.headers['x-vercel-ip-country'] || null }));
};
