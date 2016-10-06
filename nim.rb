require 'faraday'
require 'json'
require 'inifile'
require 'time'
require 'open-uri'

conf = IniFile.load("token.conf")

uri = "https://api-fxtrade.oanda.com/"
connect = Faraday::Connection.new(:url => uri) do |builder|
  builder.use Faraday::Request::UrlEncoded
  builder.use Faraday::Adapter::NetHttp
end

response_bullish = connect.get do |request|
  request.url "labs/v1/signal/autochartist&type=keylevel&direction=bullish"
  request.headers = {
      'Authorization' => "Bearer #{conf['conf']['token']}"
  }
end

response_bearish = connect.get do |request|
  request.url "labs/v1/signal/autochartist&type=keylevel&direction=bearish"
  request.headers = {
      'Authorization' => "Bearer #{conf['conf']['token']}"
  }
end

response_orders = connect.get do |request|
  request.url "v1/accounts/#{conf['conf']['account']}/orders"
  request.headers = {
      'Authorization' => "Bearer #{conf['conf']['token']}"
  }
end

response_positions = connect.get do |request|
  request.url "v1/accounts/#{conf['conf']['account']}/positions"
  request.headers = {
      'Authorization' => "Bearer #{conf['conf']['token']}"
  }
end

response_account = connect.get do |request|
  request.url "v1/accounts/#{conf['conf']['account']}"
  request.headers = {
      'Authorization' => "Bearer #{conf['conf']['token']}"
  }
end

response_trades = connect.get do |request|
  request.url "v1/accounts/#{conf['conf']['account']}/trades"
  request.headers = {
      'Authorization' => "Bearer #{conf['conf']['token']}"
  }
end


orders = JSON.parser.new(response_orders.body).parse
positions = JSON.parser.new(response_positions.body).parse
account = JSON.parser.new(response_account.body).parse
trades = JSON.parser.new(response_trades.body).parse

margin=(account['marginUsed']/account['balance']*100).to_i

holds=[]
sholds=[]
bholds=[]

orders['orders'].each { |order|
    holds.push(order['instrument'])
    if(order['side']=='buy') 
      bholds.push(order['instrument'])
    else
      sholds.push(order['instrument'])
    end
}

positions['positions'].each { |position|
    holds.push(position['instrument'])
    if(position['side']=='buy')
      bholds.push(position['instrument'])
    else
      sholds.push(position['instrument'])
    end
}

p holds


p "==================================mod=================================="
trades['trades'].each { |trade|
    if(trade['side']=='sell')
        if( (Time.now - Time.parse(trade['time'])) / (24*60*60) >= 0.5)
	  
          instrument = trade['instrument']
          p instrument

          precision = connect.get do |request|
            request.url "v1/instruments?accountId=#{conf['conf']['account']}&instruments=#{instrument}&fields=precision"
            request.headers = {
              'Authorization' => "Bearer #{conf['conf']['token']}"
            }
          end 

          prec_data = JSON.parser.new(precision.body).parse
          if prec_data['code'] == 43
            next
          end
          p = prec_data['instruments'][0]['precision']
          p p
          p trade['price'].to_f
          prec = p.to_f.to_s.sub("1.0e-","").to_i
	  p (trade['price'].to_f - p.to_f).round(prec)
        end
    end
}


p "==================================buy=================================="

json = JSON.parser.new(response_bullish.body)
data = json.parse

data['signals'].each { |signal|
  instrument = signal['instrument']
  pattern = signal['meta']['pattern']

  if "Pennant".include?(pattern)
    next
  end

  if !signal['data']['points']['keytime'].nil?
    next
  end

  if margin >= 50
    next
  end
  
  probability = signal['meta']['probability']
  support_y1 = signal['data']['points']['support']['y1']
  resistance_y1 = signal['data']['points']['resistance']['y1']
  prediction_price = signal['data']['prediction']['pricelow']
  starttime = signal['data']['prediction']['timefrom']
  endtime = signal['data']['patternendtime']
  direction = signal['meta']['direction']

  if holds.include?(instrument)
    next
  end

  if probability >=65 && direction == 1
      if (Time.at(endtime) <= Time.now)
        p "==========#{instrument}(#{probability}%)[#{pattern}]=========="
        p "price #{resistance_y1} and #{prediction_price}"
        p "order price: #{resistance_y1 - (resistance_y1 - support_y1) * 0.2}"
        p "target price: #{resistance_y1 + (prediction_price - resistance_y1) * 0.2}"
        p Time.at(endtime)

	sleep 1
	precision = connect.get do |request|
  	  request.url "v1/instruments?accountId=#{conf['conf']['account']}&instruments=#{instrument}&fields=precision"
          request.headers = {
          'Authorization' => "Bearer #{conf['conf']['token']}"
          }
        end

        prec=5
        prec_data = JSON.parser.new(precision.body).parse
        if prec_data['code'] == 43
          next
        else

	prec_data['instruments'].each { |instrument|
                prec= instrument['precision'].to_f.to_s.sub("1.0e-","").to_i
        }
        p prec
        end

        res = connect.post do |request|
          request.url "v1/accounts/#{conf['conf']['account']}/orders"
          request.headers = {
              'Authorization' => "Bearer #{conf['conf']['token']}"
          }
          request.body = {
              :instrument => instrument,
              :units  => 50,
              :side => :buy,
              :type => :marketIfTouched,
              :expiry => ((Time.now + 3600).utc.to_datetime.rfc3339),
              :price => (resistance_y1 - (resistance_y1 - support_y1) * 0.05).round(prec),
              :takeProfit => (resistance_y1 + (prediction_price - resistance_y1).abs * 0.2).round(prec)
          }
        end
      end
    end
}

p "==================================sell=================================="

json = JSON.parser.new(response_bearish.body)
data = json.parse

data['signals'].each { |signal|
  instrument = signal['instrument']
  pattern = signal['meta']['pattern']

  if "Pennant".include?(pattern)
    next
  end

  if !signal['data']['points']['keytime'].nil?
    next
  end

  if margin >= 50
    next
  end

  probability = signal['meta']['probability']
  support_y1 = signal['data']['points']['support']['y1']
  resistance_y1 = signal['data']['points']['resistance']['y1']
  prediction_price = signal['data']['prediction']['pricelow']
  starttime = signal['data']['prediction']['timefrom']
  endtime = signal['data']['patternendtime']
  direction = signal['meta']['direction']

  if holds.include?(instrument)
    next
  end

  if probability >=65 && direction == -1
      if (Time.at(endtime) <= Time.now)
        p "==========#{instrument}(#{probability}%)[#{pattern}]=========="
        p "price #{support_y1} and #{prediction_price}"
        p "order price: #{support_y1 + (resistance_y1 - support_y1) * 0.1}"
        p "target price: #{support_y1 + (prediction_price - support_y1) * 0.2}"
        p Time.at(endtime)

	sleep 1
        precision = connect.get do |request|
          request.url "v1/instruments?accountId=#{conf['conf']['account']}&instruments=#{instrument}&fields=precision"
          request.headers = {
          'Authorization' => "Bearer #{conf['conf']['token']}"
          }
        end

        prec=5
        prec_data = JSON.parser.new(precision.body).parse
	if prec_data['code'] == 43
	  next
	else

	prec_data['instruments'].each { |instrument|
                prec= instrument['precision'].to_f.to_s.sub("1.0e-","").to_i
        }
	end

        res = connect.post do |request|
          request.url "v1/accounts/#{conf['conf']['account']}/orders"
          request.headers = {
              'Authorization' => "Bearer #{conf['conf']['token']}"
          }
          request.body = {
              :instrument => instrument,
              :units  => 50,
              :side => :sell,
              :type => :marketIfTouched,
              :expiry => ((Time.now + 3600).utc.to_datetime.rfc3339),
              :price => (support_y1 + (resistance_y1 - support_y1) * 0.05).round(prec),
              :takeProfit => (support_y1 - (prediction_price - support_y1).abs * 0.2).round(prec)
          }
        end
        p res
      end
    end
}
