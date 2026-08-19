FROM pasarguard/panel:latest

COPY start-railway.sh /start-railway.sh
RUN chmod +x /start-railway.sh

ENTRYPOINT ["/start-railway.sh"]
