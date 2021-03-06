defmodule Alice.Database do
  # TODO: Consider moving this elsewhere. Same with cache.ex

  @users "users"
  @guilds "guilds"

  @pool pool: DBConnection.Poolboy
  @update_args [pool: DBConnection.Poolboy, upsert: true]

  require Logger

  ##########################
  # Guild-level operations #
  ##########################

  def get_guild(guild) do
    guild = handle_in guild
    res = Mongo.find_one :mongo, @guilds, %{"id": guild}, @pool
    if is_nil res do
      Mongo.update_one :mongo, @guilds, %{"id": guild}, %{"$set": %{"id": guild}}, @update_args
      get_guild guild
    else
      res
    end
  end

  def set_radio(guild, station) when is_map(station) do
    guild = handle_in guild
    Mongo.update_one :mongo, @guilds, %{"id": guild}, %{"$set": %{"radio": station}}, @update_args
  end

  def get_radio(guild) do
    guild = handle_in guild
    entity = get_guild guild
    if is_nil entity["radio"] do
      # Grab a random station
      station = Alice.ApiClient.radio :random, ""
      # Update the entity
      Mongo.update_one :mongo, @guilds, %{"id": guild}, %{"$set": %{"radio": station}}, @update_args
      # Return the station
      station
    else
      entity["radio"]
    end
  end

  def get_guild_settings(guild) do
    guild = handle_in guild
    settings = get_guild(guild)["settings"]
    settings = if is_nil settings do
            Mongo.update_one :mongo, @guilds, %{"id": guild}, %{"$set": %{"settings": %{}}}, @update_args
            %{}
          else
            settings
          end
    settings
  end

  def get_guild_setting(guild, setting) when is_binary(setting) do
    get_guild_settings(guild)[setting]
  end

  def set_guild_setting(guild, setting, value) when is_binary(setting) do
    guild = handle_in guild
    Mongo.update_one :mongo, @guilds, %{"id": guild}, %{"$set": %{"settings.#{setting}": value}}, @update_args
  end

  def get_custom_prefix(guild) do
    guild = handle_in guild
    get_guild_setting guild, "custom_prefix"
  end

  def set_custom_prefix(guild, prefix) when is_binary(prefix) do
    set_guild_setting guild, "custom_prefix", prefix
  end

  def get_language(guild) do
    guild = handle_in guild
    lang = get_guild_setting guild, "lang"
    if is_nil lang do
      set_language guild, "en"
      "en"
    else
      lang
    end
  end

  def set_language(guild, lang) when is_binary(lang) do
    if lang in Alice.I18n.get_langs() do
      set_guild_setting guild, "lang", lang
      {:ok, nil}
    else
      {:error, :invalid_lang}
    end
  end

  #########################
  # User-level operations #
  #########################

  def get_user(user) do
    user = handle_in user
    Mongo.find_one :mongo, @users, %{"id": user}, @pool
  end

  def get_achievements(user) do
    achievements = get_user(user)["achievements"]
    if is_nil achievements do
      # Do... something, I guess
      Mongo.update_one :mongo, @users, %{"id": user}, %{"$set": %{"achievements": %{}}}, @update_args
      %{}
    else
      achievements
    end
  end

  def set_achievement(user, achievement, value) when is_binary(achievement) and is_boolean(value) do
    user = handle_in user
    Mongo.update_one :mongo, @users, %{"id": user}, %{"$set": %{"achievements.#{achievement}": value}}, @update_args
  end

  def has_achievement?(user, achievement) when is_binary(achievement) do
    user = handle_in user
    achievements = get_achievements user

    if Map.has_key?(achievements, achievement) do
      # If it's present, return the value at it
      achievements[achievement]
    else
      # It's not present, insert false and send that back
      set_achievement user, achievement, false
      false
    end
  end

  #######################
  # Currency operations #
  #######################

  def increment_balance(user, amount) when is_integer(amount) do
    user = handle_in user
    Mongo.update_one :mongo, @users, %{"id": user}, %{"$inc": %{"currency.balance": amount}}, @update_args
  end

  def set_balance(user, amount) when is_integer(amount) do
    user = handle_in user
    Mongo.update_one :mongo, @users, %{"id": user}, %{"$set": %{"currency.balance": amount}}, @update_args
  end

  def balance(user) do
    user = handle_in user
    balance = get_user(user)["currency"]["balance"]
    if is_nil balance do
      set_balance user, 0
      0
    else
      balance
    end
  end

  def balance_top do
    Mongo.aggregate :mongo, @users, [
        %{"$sort": %{"currency.balance": -1}},
        %{"$limit": 10}
      ], pool: DBConnection.Poolboy
  end

  def set_last_daily(user, timestamp) do
    user = handle_in user
    Mongo.update_one :mongo, @users, %{"id": user}, %{"$set": %{"currency.last_daily": timestamp}}, @update_args
  end

  def get_last_daily(user) do
    user = handle_in user
    get_user(user)["currency"]["last_daily"]
  end

  def set_currency_daily_streak(user, streak) when is_integer(streak) do
    user = handle_in user
    Mongo.update_one :mongo, @users, %{"id": user}, %{"$set": %{"currency.streak": streak}}, @update_args
  end

  def incr_currency_daily_streak(user) do
    user = handle_in user
    Mongo.update_one :mongo, @users, %{"id": user}, %{"$inc": %{"currency.streak": 1}}, @update_args
  end

  def get_currency_daily_streak(user) do
    user = handle_in user
    streak = get_user(user)["currency"]["streak"]
    if is_nil streak do
      set_currency_daily_streak user, 0
      0
    else
      streak
    end
  end

  #####################
  # Levels operations #
  #####################

  # Global levels #

  def get_xp(user) do
    user = handle_in user
    xp = get_user(user)["xp"]
    if is_nil xp do
      set_xp user, 0
      0
    else
      xp
    end
  end

  def increment_xp(user, amount) when is_integer(amount) do
    user = handle_in user
    Mongo.update_one :mongo, @users, %{"id": user}, %{"$inc": %{"xp": amount}}, @update_args
  end

  def set_xp(user, amount) when is_integer(amount) do
    user = handle_in user
    Mongo.update_one :mongo, @users, %{"id": user}, %{"$set": %{"xp": amount}}, @update_args
  end

  # Guild levels #

  def get_guild_xp(user, guild) do
    user = handle_in(user) |> Integer.to_string
    guild = guild |> handle_in |> get_guild
    if is_nil guild["xp"][user] do
      set_guild_xp user, guild["id"], 0
      0
    else
      guild["xp"][user]
    end
  end

  def increment_guild_xp(user, guild, amount) when is_integer(amount) do
    try do
      user = handle_in(user) |> Integer.to_string
      guild = handle_in guild
      res = Mongo.update_one :mongo, @guilds, %{"id": guild}, %{"$inc": %{"xp.#{user}": amount}}, @update_args
      Logger.debug "Incremented guild xp by #{inspect amount}"
      Logger.debug "MongoDB response: #{inspect res, pretty: true}"
    rescue
      e -> Logger.warn "#{inspect e, pretty: true} - #{inspect System.stacktrace(), pretty: true}"
    end
  end

  def set_guild_xp(user, guild, amount) when is_integer(amount) do
    user = handle_in(user) |> Integer.to_string
    guild = handle_in guild
    Mongo.update_one :mongo, @guilds, %{"id": guild}, %{"$set": %{"xp.#{user}": amount}}, @update_args
    Logger.debug "Set guild xp to #{inspect amount}"
  end

  ####################
  # Emote operations #
  ####################

  def get_emotes(name) when is_binary(name) do
    # TODO: Magic constant from cache.ex, uses cache pool
    Mongo.aggregate :mongo_cache, "emoji_cache", [
        %{"$match": %{"name": name}},
        %{"$sort": %{"guild_id": 1}}
      ], pool: DBConnection.Poolboy
  end

  ##########################################
  ## INTERNAL API STARTS BEYOND THIS LINE ##
  ##                                      ##
  ## UNLESS YOU ARE CHASING DOWN A BUG,   ##
  ## THIS IS MOST DEFINITELY NOT WHAT YOU ##
  ## WANT TO BE TOUCHING!                 ##
  ##########################################

  #####################################################################################################################

  ####################
  # Helper functions #
  ####################

  defp handle_in(entity) do
    # Can't case here :^(
    if is_map(entity) do
      handle_in(entity["id"])
    else
      if is_binary(entity) do
        String.to_integer(entity)
      else
        if is_integer(entity) do
          entity
        else
          raise "Invalid DB entity input: #{inspect entity}"
        end
      end
    end
  end
end