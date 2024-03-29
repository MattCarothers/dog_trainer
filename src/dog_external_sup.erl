-module(dog_external_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  {ok,Links} = dog_link:dump_all(),
  {ok, {{one_for_one, 5, 60},
        lists:map(fun(Link) ->
                      LinkName = maps:get(<<"name">>,Link),
                      EnvName = LinkName,
                      lager:debug("LinkName: ~p",[LinkName]),
                      {EnvName,
                       {dog_external_agent, start_link, [Link]},
                       permanent,
                       5000,
                       worker,
                       [dog_external_agent]}
                  end,Links)
       }}.
