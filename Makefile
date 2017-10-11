IMAGE_NAME=jipund/alpine-strongswan-vpn

all:
	docker build -t $(IMAGE_NAME) .

clean:
	docker rmi $(IMAGE_NAME) || true
