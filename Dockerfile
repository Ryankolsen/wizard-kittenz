FROM heroiclabs/nakama:3.22.0
COPY nakama-start.sh /nakama-start.sh
COPY nakama-config.yml /nakama-config.yml
RUN chmod +x /nakama-start.sh
EXPOSE 7350
ENTRYPOINT ["/nakama-start.sh"]
