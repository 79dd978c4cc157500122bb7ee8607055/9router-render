# 9router di Render Free — tambah lapisan restore/backup SQLite
FROM decolua/9router:latest

# boot.sh: restore DB dari backup store → jalankan 9router → backup berkala
COPY boot.sh /usr/local/bin/r9boot.sh
RUN chmod 755 /usr/local/bin/r9boot.sh

# Base image: ENTRYPOINT ["/entrypoint.sh"], CMD ["node","custom-server.js"]
# → entrypoint menjalankan `exec su-exec node "$@"`, jadi CMD ini dieksekusi sbg node
CMD ["/usr/local/bin/r9boot.sh"]
