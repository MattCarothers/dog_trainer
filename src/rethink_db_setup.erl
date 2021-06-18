-module(rethink_db_setup).

-include("dog_trainer.hrl").

-export([
         setup_rethinkdb/4
        ]).

-export([
         get_connection/4,
         ensure_db_exists/2
        ]).

-spec table_schema() -> map().
table_schema() ->
  #{ 
    <<"external">> => [<<"name">>],
    <<"group">> => [<<"name">>, <<"profile_id">>],
    <<"host">> => [<<"group">>,<<"hostkey">>,<<"hostname">>,<<"name">>],
    <<"ipset">> => [<<"name">>,<<"timestamp">>],
    <<"link">> => [<<"name">>],
    <<"profile">> => [<<"docker">>,<<"name">>],
    <<"service">> => [<<"name">>],
    <<"zone">> => [<<"name">>]
   }.

-spec setup_rethinkdb(Hostname :: string(), Port :: integer(), Username :: string(), Password :: string()) -> map().
setup_rethinkdb(Hostname,Port,Username,Password) ->
  Connection = get_connection(Hostname,Port,Username,Password),
  ensure_db_exists(Connection,?DB_NAME),
  maps:map(fun(TableName,FieldsList) ->
               ensure_table_exists(Connection,?DB_NAME,TableName),
               maps:from_list(lists:map(fun(FieldName) ->
                             {FieldName,ensure_index_exists(Connection,?DB_NAME,TableName,FieldName)}
                         end, FieldsList))
           end, table_schema()).

-spec get_connection(Hostname :: string(),Port :: integer(), Username :: string(),Password :: string()) -> pid().
get_connection(Hostname,Port,Username,Password) ->
  {ok, Connection} = gen_rethink:connect(#{host => Hostname, port => Port, id => Username, password => Password }),
  Connection.
 
-spec ensure_db_exists(Connection :: pid(),DatabaseName :: binary()) -> ok | change.
ensure_db_exists(Connection,DatabaseName) ->
  {ok, Databases} = gen_rethink:run(Connection,
                               fun(X) ->
                                   reql:db_list(X)
                               end),
  case lists:member(DatabaseName, Databases) of
    true ->
      io:format("ok: Database already exists: ~p~n",[DatabaseName]),
      ok;
    false ->
      io:format("change: Creating database: ~p~n",[DatabaseName]),
      create_db(Connection, DatabaseName),
      change
  end.

create_db(Connection,DatabaseName) ->
  {ok, _Response} = gen_rethink:run(Connection, fun(X) -> reql:db_create(X, DatabaseName) end).

-spec ensure_table_exists(Connection :: pid() ,DatabaseName :: binary(),TableName :: string()) -> ok | change.
ensure_table_exists(Connection,DatabaseName,TableName) ->
  {ok, Tables } = gen_rethink:run(Connection,
                               fun(X) ->
                                   reql:db(X, DatabaseName),
                                   reql:table_list(X)
                               end),
  case lists:member(TableName, Tables) of
    true ->
      io:format("ok: Table already exists: ~p~n",[TableName]),
      ok;
    false ->
      io:format("change: Creating table: ~p~n",[TableName]),
      create_table(Connection,DatabaseName,TableName),
      change
  end.

-spec create_table(Connection :: pid(), DatabaseName :: binary(), TableName :: string()) -> {ok, map()}.
create_table(Connection,DatabaseName,TableName) -> 
  {ok, #{} } = gen_rethink:run(Connection,
                               fun(X) ->
                                   reql:db(X, DatabaseName),
                                   reql:table_create(X, TableName)
                               end).

-spec ensure_index_exists(Connection :: pid(),DatabaseName :: binary(),
                          TableName :: string(),FieldName :: string()) -> ok | change.
ensure_index_exists(Connection,DatabaseName,TableName,FieldName) ->
   {ok, Indexes} = gen_rethink:run(Connection, 
																	fun(X) -> 
																		reql:db(X, DatabaseName),
																	  reql:table(X, TableName),
																		reql:index_list(X)
																	end),
  case lists:member(FieldName, Indexes) of
    true ->
      io:format("ok: Index on ~p in table ~p already exists~n",[FieldName,TableName]),
      ok;
    false ->
      io:format("change: Creating index on ~p in table ~p~n",[FieldName,TableName]),
      create_index(Connection,TableName,FieldName),
      change
  end.

create_index(Connection,TableName,FieldName) ->
  {ok,_Map} = gen_rethink:run(Connection,
                               fun(X) ->
                                   reql:db(X, dog),
                                   reql:table(X, TableName),
                                   reql:index_create(X, FieldName)
                               end).