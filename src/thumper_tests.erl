-module(thumper_tests).

-define(Exchange, <<"exchange">>).
-define(Queue, <<"queue">>).
-define(ConsumeTimeout, 60000).

-include("dog_trainer.hrl").
-include_lib("./_build/default/lib/thumper/include/thumper.hrl").

-export [
        setup/0
        ].


setup() ->
    application:load(thumper),
    application:set_env(thumper, thumper_svrs, []),

    {ok, _} = application:ensure_all_started(erlexec),
    {ok, _} = application:ensure_all_started(thumper),

    %{ok, Server} = rmqs:start_link(#{port => 0}),
    %unlink(Server),
    %Port = rmqs:get_port(Server),
    %true = tcp_reachable(Port, 60000),
    Port = 5673,

    RmqConfig = [{host, "10.216.205.246"},
                 {port, Port},
                 {user, <<"dog_trainer">>},
                {password, <<"327faf06-c3f5-11e7-9765-7831c1be5b34">>},
                        {ssl_options, [{cacertfile, "/var/consul/data/pki/certs/ca.crt"},
                                       {certfile, "/var/consul/data/pki/certs/server.crt"},
                                       {keyfile, "/var/consul/data/pki/private/server.key"},
                                       {verify, verify_peer},
                                       {server_name_indication, disable},
                                       {fail_if_no_peer_cert, true}
                                      ]},
                 {virtual_host, <<"dog">>}],

    application:set_env(thumper, queuejournal, [{enabled, true},
                                                {memqueue_max, 10000},
                                                {check_journal, true},
                                                {dir, "/tmp/queuejournal"}]),

    application:set_env(thumper, brokers, [{default, [{rabbitmq_config, RmqConfig}]},
                                           {local, [{rabbitmq_config, RmqConfig}]}]),

    ok = thumper_tx:run(
           [{rabbitmq_config, RmqConfig},
            {tx, [
                  {'exchange.declare', [
                                        {exchange, ?Exchange},
                                        {type, <<"fanout">>},
                                        {durable, false}
                                       ]},
                  {'queue.declare', [
                                     {queue, ?Queue},
                                     {durable, false},
                                     {auto_delete, false}
                                    ]},
                  {'queue.bind', [
                                  {queue, ?Queue},
                                  {exchange, ?Exchange},
                                  {routing_key, <<>>}
                                 ]}
                 ]
            }]),

    supervisor:start_child(thumper_sup, thumper_sup:child_spec(default)),
    supervisor:start_child(thumper_sup, thumper_sup:child_spec(local)),

    timer:sleep(1000),

    %% make sure we have connections
    #state{broker_handle=#broker_handle{}} = thumper:get_state(default),
    #state{broker_handle=#broker_handle{}} = thumper:get_state(local).

    %#{rmqs => Server}.

publish_to_queue(RoutingKey, R4IpsetsRuleset, R6IpsetsRuleset, R4IptablesRuleset, R6IptablesRuleset, Ipsets) ->
    ?LOG_INFO("RoutingKey: ~p",[RoutingKey]),
    UserData = #{
      ruleset4_ipset => R4IpsetsRuleset,
      ruleset6_ipset => R6IpsetsRuleset,
      ruleset4_iptables => R4IptablesRuleset,
      ruleset6_iptables => R6IptablesRuleset,
      ipsets => Ipsets
                },
    Count = 1,
    Pid = erlang:self(),
    Message = term_to_binary([{count, Count}, {local_time, calendar:local_time()}, {pid, Pid}, {user_data, UserData}]),
    Response = thumper:publish(Message, ?IptablesExchange, RoutingKey),
    Response.

subscribe_to_queue(#{broker := Broker,
                name := Name, queue := QueueName}) ->
    Callback = fun (A, B, C) ->
               subscriber_callback(A, B, C)
           end,
    case dog_thumper_sup:ensure_consumer(up, Name, Broker,
                     QueueName, Callback)
    of
      {ok, _ChildPid} -> 
        ok;
      {error, {already_up, _ChildPid}} -> 
        ok
    end.

-spec subscriber_callback(DeliveryTag :: binary() , RoutingKey :: binary() ,Payload :: binary()) -> 'ack'. 
subscriber_callback(_DeliveryTag, _RoutingKey, Payload) ->
    Proplist = binary_to_term(Payload),
    UserData = proplists:get_value(user_data, Proplist),
    ?LOG_DEBUG("UserData: ~p",[UserData]),
    ExternalEnv = jsn:as_map(jsx:decode(maps:get(ipsets, UserData))),
    ?LOG_DEBUG("ExternalEnv: ~p",[ExternalEnv]),
    ExternalEnvName = maps:get(<<"name">>,ExternalEnv),
    ?LOG_INFO("external ipsets receieved: ~p",[ExternalEnvName]),
    ack.

consume_n(Broker, Queue, N) ->
    Ref = make_ref(),
    Me = self(),
    Callback = fun(DT, RK, Payload) ->
                       Me ! {Ref, {DT, RK, Payload}},
                       ack
               end,
    {ok, ConsumerPid} = thumper_consumer:start_link(undefined, Broker, Queue, Callback),
    ?LOG_DEBUG("created consumer ~p", [ConsumerPid]),
    fun Rcv(0, Acc) ->
            unlink(ConsumerPid),
            thumper_consumer:stop(ConsumerPid),
            {ok, lists:reverse(Acc)};
        Rcv(N0, Acc) ->
            receive
                {Ref, {_DT, _RK, Payload}} ->
                    Rcv(N0-1, [binary_to_term(Payload)|Acc])
            after ?ConsumeTimeout ->
                      {error, timeout}
            end
    end(N, []).

%% =========================
tcp_reachable(_, T) when T =< 0 ->
    false;
tcp_reachable(Port, Timeout) ->
    Host = "127.0.0.1",
    case gen_tcp:connect(Host, Port, []) of
        {ok, Socket} ->
            gen_tcp:close(Socket),
            true;
        _ ->
            timer:sleep(1000),
            tcp_reachable(Port, Timeout-1000)
    end.
