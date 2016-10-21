class CachedResult
  currentTTL: null
  result: null

  constructor: (result, TTL = 5) ->
    @currentTTL = TTL
    @result = result

  getResult: =>
    if do @valid
      @currentTTL -= 1
      @result
    else
      null

  valid: =>
    @currentTTL > 0

module.exports = CachedResult
