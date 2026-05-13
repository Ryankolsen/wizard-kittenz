FROM heroiclabs/nakama:3.22.0
COPY nakama-start.sh /nakama-start.sh
RUN chmod +x /nakama-start.sh
EXPOSE 7350
ENTRYPOINT ["/nakama-start.sh"]
