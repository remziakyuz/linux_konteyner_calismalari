Merhaba,
github 100MB buyuk dosyalara izin vermediği için parçalanmıştır.
Kullanmak için aşağıdaki komutla oluşturulan tar dosyasını kullanınız.
cat guesbook-backup.tar.part* > guesbook-lab-calismasi-konteyner-image-backup.tar

konteyner image yuklemek için;

 podman load -i guesbook-lab-calismasi-backup.tar

