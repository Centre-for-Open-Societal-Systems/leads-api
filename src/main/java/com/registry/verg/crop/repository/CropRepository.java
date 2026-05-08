package com.registry.verg.crop.repository;

import com.registry.verg.crop.entity.CropEntity;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CropRepository extends JpaRepository<CropEntity, String> {

}