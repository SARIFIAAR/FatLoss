FROM node:22-slim
WORKDIR /app
ENV NODE_ENV=production
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ && rm -rf /var/lib/apt/lists/*
COPY package*.json ./
RUN npm ci --omit=dev
COPY server.js firestore.js admin.html ./
COPY data/foods.db ./data/foods.db
EXPOSE 8080
CMD ["node", "server.js"]
