# Note this is using the "new" Alert system from New Relic.
# This system is in beta at time of writing: https://docs.newrelic.com/docs/alerts/new-relic-alerts-beta
require 'httparty'

SCHEDULER.every '1m', :first_in => 0 do |job|

  parameters = settings.use_new_relic_alerts
  return unless parameters

  truncator = RocketDashing::Truncator.new

  api_key = parameters.need(:api_key)

  total_policy_count = HTTParty.get(
      'https://api.newrelic.com/v2/alerts_policies.json',
      {
          headers: {'X-Api-Key' => api_key}
      }
  )['policies'].count

  policy_violations = []
  has_critical_violations = false
  policy_ids_violated = {}

  HTTParty.get(
                         'https://api.newrelic.com/v2/alerts_violations.json',
                         {
                             query: {'only_open' => 'true'},
                             headers: {'X-Api-Key' => api_key}
                         }
  )['violations'].each do |violation|
    has_critical_violations = true if !has_critical_violations && violation['priority'].downcase == 'critical'

    policy_ids_violated[violation['links']['policy_id']] = true

    policy_violations << {cols: [
        {value: truncator.truncate(violation['condition_name'], 16)},
        {value: truncator.truncate(violation['entity']['name'], 16)}
    ]}
  end

  color = 'green'
  if has_critical_violations
    color = 'red'
  elsif policy_violations.count > 1
    color = 'yellow'
  end

  send_event 'new-relic-policies-ok', {
                                       value: "#{total_policy_count - policy_ids_violated.keys.count}/#{total_policy_count}",
                                       color: color
                                   }
  send_event 'new-relic-alerts', {
                                           rows: policy_violations,
                                           moreinfo: "#{policy_violations.count} problems",
                                           color: color
                                       }
end