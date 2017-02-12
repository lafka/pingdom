use Mix.Config

config :pingdom, :backend, "https://status.tiny-mesh.com/api"
# maximum items to keep in log
config :pingdom, :backlog, 1000
# don't keep items that's older than 6 hours
config :pingdom, :ttl, 3600000 * 6
config :pingdom, :cachet_token, "9Ib9MnjeR8WStYtQs0rU"

if :test === Mix.env do
  config :pingdom, :metrics, %{}
else
  config :pingdom, :metrics, %{}
end
