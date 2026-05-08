package com.registry.verg.vergsample.repository;


import com.registry.verg.vergsample.entity.SampleEntity;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SampleRepository extends JpaRepository<SampleEntity, String> {

}